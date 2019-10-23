/*
涂轶翔：
此模块用来将已经展开的包内容进行处理，
但是 IP 包的 Data 除外，它应当由 io_manager 直接转发

todo: 处理中间突然结束的包
todo: 处理错误格式的包

时序：
-   io_manager 开始收包，packet_arrive 置一拍 1
-   io_manager 在接收的同时告诉此模块已经收到了多少字节，
    收到的数据会同时传递给 frame_in
    （会比 io_manager 慢一拍）
-   此模块检查信息，能够在包读完之前知道当前这个包有多长，
    对于 IP 包，会提前计算头长度，让 io_manager 从那里开始自己直接转发
    -   发现是 IP 包后（且后面有 data 需要直接转发）：
        require_direct_fw 置 1
        direct_fw_offset 置 data 开始的位置
    -   io_manager 停在 direct_fw_offset 的位置
        rx_ready 置 0，等待此模块处理完
    -   此模块生成新的 header 在 frame_out
        其长度在 out_bytes （默认 20）
        out_ready 置 1
    -   io_manager 把新的 header 发走，然后继续读 fifo 直接转发
-   随时，此模块可能发现包不合法
    bad 置 1，io_manager 看到直接走丢包流程

工作流程：
读取至 18 字节，如果协议不是 ARP 或者 IP 则丢包（置 bad）
读取至 22 字节，检查是否是带有 data 的 IP 包
    如是则置 require_direct_fw
    如否则等 io_manager 读完整个包
读完后（或读到 data 前），查表
查完表输出结果

ARP 包网帧：
0   [367:320]   目标 MAC
6   [319:272]   来源 MAC
12  [271:256]   0x8100  VLAN
14  [255:240]   [241:240] 为 VLAN ID
16  [239:224]   0x0806  ARP
18  [223:208]   0x0001  以太网
20  [207:192]   0x8000  IPv4
22  [191:184]   0x06    硬件地址长度
23  [183:176]   0x04    协议地址长度
24  [175:160]   0x0001  ARP Request
26  [159:112]   来源 MAC
32  [111:80 ]   来源 IP
36  [ 79:32 ]   目标 MAC (全 0)
42  [ 31:0  ]   目标 IP
46

IP  包网帧：
0   [367:320]   目标 MAC
6   [319:272]   来源 MAC
12  [271:256]   0x8100  VLAN
14  [255:240]   [241:240] 为 VLAN ID
16  [239:224]   0x0800  IPv4
18  [223:216]   0x45    Protocol v4, header 大小 20B
19  [215:208]   0x00    DSF
20  [207:192]   IP 包长度
22  [191:176]   连续包识别码
24  [175:160]   [174]=DF, [173]=MF, [172:160]=Offset （用于分包）
26  [159:152]   TTL
27  [151:144]   IP 协议
28  [143:128]   Checksum
30  [127:96 ]   目标 IP
34  [ 95:64 ]   来源 IP
38
*/

`include "debug.vh"
`include "address.vh"

module packet_manager (
    input   wire    clk,                // 父模块同步时钟
    input   wire    rst,                // 父模块同步复位

    input   wire    packet_arrive,      // 开始收包，置一拍 1

    input   wire    [367:0] frame_in,   // 输入以太网帧
    input   byte    bytes_read,         // 已经读取的字符数

    output  bit     bad,                // 包不可用，该丢掉

    output  bit     [367:0] frame_out,  // 输出以太网帧
    output  bit     out_ready,          // 输出已处理完毕
    output  byte    out_bytes,          // 输出网帧大小（字节）

    output  bit     require_direct_fw,  // 要求父模块进行直接转发
    output  byte    direct_fw_offset,   // 从哪里开始直接转发
    output  int     fw_bytes            // 转发大小（字节）
);

`define BAD_EXIT(msg) \
    bad <= 1; \
    state <= Idle; \
    $display("%s", {"BAD PACKET: ", msg});

enum {
    Idle,       // 空闲
    Receiving,  // 正在和 io_manager 同步接收包
    IpRunning,  // 正在用子模块处理生成新网帧
    ArpRunning, // 正在用子模块处理生成新网帧
    Test
} state;

enum {
    ARP,
    IPv4
} protocol;     // 目前读取的网帧采用的协议，在读取 18 字节后确定

always_ff @ (posedge clk or posedge rst) begin
    if (rst) begin
        // 复位
        state <= Idle;
        bad <= 0;
        out_ready <= 0;
        out_bytes <= 0;
        require_direct_fw <= 0;
        direct_fw_offset <= 0;

        // test
        // state <= Test;
        // out_bytes <= 46;
        // out_ready <= 1;
        // frame_out <= 368'h00E04C6806E2A888088888888100000008060001080006040002A888088888880606060600E04C6806E206060601;
    end else if (packet_arrive) begin
        // 开始接收数据包
        if (state != Idle) begin
            $display("ERROR: packet_manager packet_arrive = 1 while not idle!!");
        end else begin
            state <= Receiving;
            bad <= 0;
            out_ready <= 0;
            out_bytes <= 0;
            require_direct_fw <= 0;
            direct_fw_offset <= 0;
        end
    end else begin
        case(state)
            Receiving: begin
                case(bytes_read)
                    6:  begin
                        // todo: 检查目标 MAC，若不是广播任何已知地址则丢包
                        // case(frame_in[367:320])
                        //     `ROUTER_MAC, '1: ;
                        //     default: begin
                        //         `BAD_EXIT("MAC not matched");
                        //     end
                        // endcase
                    end
                    18: begin
                        // 检查协议是否为 ARP 或 IP
                        case(frame_in[239:224])
                            16'h0806: protocol <= ARP;
                            16'h0800: protocol <= IPv4;
                            default: begin
                                `BAD_EXIT("Unsupported protocol");
                            end
                        endcase
                    end
                    22: begin
                        // 检查是否是 IP 且具有 data 包
                        if (protocol == IPv4 && frame_in[207:192] > 20) begin
                            // 具有 data 包，则需要 io_manager 从 header 结束之后直接转发 data
                            require_direct_fw <= 1;
                            direct_fw_offset <= 38;
                            fw_bytes <= frame_in[207:192] - 20;
                        end
                    end
                    27: begin
                        // 对于 IP 包，如果 TTL 为零则丢弃
                        if (protocol == IPv4 && frame_in[159:152] == '0) begin
                            `BAD_EXIT("TTL = 0");
                        end
                    end
                    38: begin
                        // todo: 把赋值操作摊到之前的时候
                        // 如果是 IP 包，这里要开始处理
                        if (protocol == IPv4) begin
                            state <= IpRunning;
                            // 一些东西可以直接填充
                            // [367:320]    查表 MAC
                            frame_out[319:272] <= frame_in[367:320];
                            frame_out[271:242] <= frame_in[271:242];
                            // [241:240]    查表 VLAN ID
                            frame_out[239:160] <= frame_in[239:160];
                            frame_out[159:152] <= frame_in[159:152] - 1;
                            frame_out[151:144] <= frame_in[151:144];
                            if (frame_in[143:128] == '1)
                                frame_out[143:128] <= 16'h1;
                            else
                                frame_out[143:128] <= frame_in[143:128] + 1;
                            frame_out[127:64] <= frame_in[127:64];
                        end
                    end
                    46: begin
                        // 如果是 ARP 包，这里要开始处理
                        if (protocol == ARP) begin
                            state <= ArpRunning;
                            // 一些东西可以直接填充
                            frame_out[367:320] <= frame_in[319:272];
                            frame_out[319:272] <= `ROUTER_MAC;
                            frame_out[271:176] <= frame_in[271:176];
                            frame_out[175:160] <= 16'h2;
                            // [159:112]    查表 MAC
                            frame_out[111:80] <= frame_in[31:0];
                            frame_out[79:32] <= frame_in[159:112];
                            frame_out[31:0] <= frame_in[111:80];
                        end
                    end
                endcase
            end
            IpRunning: begin
                case(frame_in[367:320])
                    `TYX_MAC: begin
                        frame_out[367:320] <= `TYX_MAC;
                        frame_out[241:240] <= `TYX_PORT;
                    end
                    `ZCG_MAC: begin
                        frame_out[367:320] <= `ZCG_MAC;
                        frame_out[241:240] <= `ZCG_PORT;
                    end
                    `WZY_MAC: begin
                        frame_out[367:320] <= `WZY_MAC;
                        frame_out[241:240] <= `WZY_PORT;
                    end
                    default: begin
                        frame_out[367:320] <= '1;
                        frame_out[241:240] <= '0;
                    end
                endcase
                out_ready <= 1;
                out_bytes <= 38;
                state <= Idle;
            end
            ArpRunning: begin
                case(frame_in[31:0])
                    `TYX_IP:    frame_out[159:112] <= `TYX_MAC;
                    `ZCG_IP:    frame_out[159:112] <= `ZCG_MAC;
                    `WZY_IP:    frame_out[159:112] <= `WZY_MAC;
                    `ROUTER_IP: frame_out[159:112] <= `ROUTER_MAC;
                    default:    frame_out[159:112] <= '0;
                endcase
                out_ready <= 1;
                out_bytes <= 46;
                state <= Idle;
            end
            default: begin
            end
        endcase
    end
end

endmodule