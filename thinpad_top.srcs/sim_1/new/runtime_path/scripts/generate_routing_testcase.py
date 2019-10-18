"""
生成 routing table 的测试用例

输出会存储到 ../routing_test.data
格式: 16 字节一条记录
insert:
    [0:3]   00 00 00 00 表示 insert
    [4:7]   80 00 00 01 表示插入地址 128.0.0.1
    [8:11]  00 00 00 10 表示 mask 长度为 16
    [12:15] 0a 00 00 01 表示 nexthop 地址 10.0.0.1
query:
    [0:3]   00 00 00 01 表示 query
    [4:7]   80 00 00 01 表示查询地址 128.0.0.1
    [8:11]  00 00 00 01 表示查询到了一条记录
            00 00 00 00 表示没有查到任何记录
    [12:15] 0a 00 00 01 表示查询到 nexthop 地址 10.0.0.1
eof:
    [0:3]   ff ff ff ff 表示结束
    [4:15]              忽略
"""
from __future__ import annotations
from typing import *
import random
import sys
import random
import os
import struct
import json


class Config:
    insertion_count = 256   # how many insertions operation to make
    query_count = 1024      # how many queries operation to make
    miss_rate = 0.25        # the ratio of queries that would miss
    order = False           # whether all queries will be after insertions
    pressure = False        # whether inserted IP addresses are condense
    path = ''               # (maybe) relative path to runtime_path directory


class IPAddress:
    value: int  # uint32 value of IP address
    mask: int   # mask length, [12, 28]
    nexthop: IPAddress
    # if '-p', random generated IP addresses will be near this center
    center: int = random.randint(0, 0xffffffff)

    @staticmethod
    def get_insert_addr() -> IPAddress:
        """
        随机生成一个带有 mask 的地址
        如果在 -p 模式下，生成的地址会集中在一个比较小的范围
        """
        if Config.pressure:
            value = int(random.normalvariate(
                IPAddress.center, 0x800000)) & 0xffffffff
        else:
            value = random.randint(0, 0xffffffff)
        mask = random.randint(12, 28)
        value &= 0xffffffff << (32 - mask)
        return IPAddress(value, mask)

    @staticmethod
    def get_query_match(target: IPAddress) -> IPAddress:
        """
        随机生成一个匹配目标地址的地址
        """
        value = target.value ^ (
            random.randint(0, 0xffffffff) & (0xffffffff >> target.mask))
        return IPAddress(value, 32)

    @staticmethod
    def get_random_addr() -> IPAddress:
        """
        随机生成一个地址
        """
        return IPAddress(random.randint(0, 0xffffffff), 32)

    def __init__(self, value: int, mask: int):
        self.value = value
        self.mask = mask
        self.nexthop = None

    @property
    def raw(self) -> bytearray:
        return struct.pack('>I', self.value)    # big-endian i32 value

    def match(self, dest: IPAddress) -> bool:
        """
        此地址是否可以匹配上 dest（路由表中的一条记录）
        """
        return self.value & (0xffffffff << (32 - dest.mask)) == dest.value

    def __getitem__(self, index) -> int:
        if type(index) is not int:
            raise TypeError()
        return self.raw[index]

    def __hash__(self):
        return self.value + hash(self.mask)

    def __eq__(self, other):
        return self.value == other.value and self.mask == other.mask

    def __str__(self):
        raw = self.raw
        if self.mask == 32:
            s = '%d.%d.%d.%d' % (raw[0], raw[1], raw[2], raw[3])
            pad = ' ' * (15 - len(s))
        else:
            s = '%d.%d.%d.%d/%d' % (raw[0], raw[1], raw[2], raw[3], self.mask)
            pad = ' ' * (18 - len(s))
        if self.nexthop is not None:
            s += ' -> ' + str(self.nexthop)
        return s + pad


class Entry:
    inserted = set()    # 已经插入的地址（用于查重）
    inserted_list = []  # 已经插入的地址（用于随机选择）
    tree = ([], {})     # 四级的树来存储已插入的地址
    counter = 0         # 已经生成的条目数量

    @staticmethod
    def _test():
        # 检验功能
        for i in range(100):
            addr = IPAddress.get_insert_addr()
            addr.nexthop = IPAddress.get_random_addr()
            Entry._save(addr)
            print('insert', addr)
        for i in range(100):
            if random.random() < 0.75:
                addr = IPAddress.get_query_match(
                    random.choice(Entry.inserted_list))
                print('selected ', end='')
            else:
                addr = IPAddress.get_random_addr()
                print('random   ', end='')
            match = Entry._match(addr)
            print(addr, 'match', match)

    @staticmethod
    def _save(addr: IPAddress):
        """
        将一个被插入的条目保存
        """
        if addr in Entry.inserted:
            raise Exception()
        Entry.inserted.add(addr)
        Entry.inserted_list.append(addr)
        target = Entry.tree
        for level in range(4):
            if addr.mask <= (level + 1) * 8:
                # 如果剩余长度小于等于八位，则用数组保存
                target[0].append(addr)
                break
            # 否则需要进入下一层树
            if addr[level] in target[1]:
                target = target[1][addr[level]]
            else:
                target[1][addr[level]] = ([], {})
                target = target[1][addr[level]]

    @staticmethod
    def _match(addr: IPAddress) -> IPAddress:
        """
        尝试从已插入的地址中寻找可以匹配当前地址的
        """
        best = None
        best_mask = 0
        target = Entry.tree
        for level in range(4):
            for dest in target[0]:
                if dest.mask > best_mask and addr.match(dest):
                    best, best_mask = dest, dest.mask
            if addr[level] in target[1]:
                target = target[1][addr[level]]
            else:
                break
        return best

    @staticmethod
    def insert() -> bytearray:
        """
        生成一条插入的数据
        """
        new_addr = IPAddress.get_insert_addr()
        while new_addr in Entry.inserted:
            new_addr = IPAddress.get_insert_addr()
        nexthop = IPAddress.get_random_addr()
        new_addr.nexthop = nexthop
        Entry._save(new_addr)
        Entry.counter += 1
        print('%d.\t\033[32minsert' % Entry.counter, new_addr, '\033[0m')
        return (
            b'\0\0\0\0' +
            new_addr.raw +
            b'\0\0\0' + struct.pack('B', new_addr.mask) +
            nexthop.raw
        )

    @staticmethod
    def query() -> bytearray:
        if random.random() < Config.miss_rate or len(Entry.inserted) == 0:
            addr = IPAddress.get_random_addr()
        else:
            addr = IPAddress.get_query_match(
                random.choice(Entry.inserted_list))
        match = Entry._match(addr)
        Entry.counter += 1
        print('%d.\t\033[33mquery ' % Entry.counter, addr, '\033[0m')
        print('\t\033[34mexpect', match, '\033[0m')
        if match is not None:
            return (
                b'\0\0\0\1' +
                addr.raw +
                b'\0\0\0\1' +
                match.nexthop.raw
            )
        else:
            return (
                b'\0\0\0\1' +
                addr.raw +
                b'\0\0\0\0' +
                b'\0\0\0\0'
            )


def wrong_usage_exit():
    print('\033[31mInvalid arguments\033[0m')
    print(
        'Arguments:',
        '-i <insert_count>',
        '\tSpecify how many routing entry to insert. Default is %d.' % Config.insertion_count,
        '-q <query_count>',
        '\tSpecify how many queries to make. Default is %d.' % Config.query_count,
        '-m <miss_rate>',
        '\tSpecify the ratio of queries that doesn\'t match any insertion. Default is %.2f.' % Config.miss_rate,
        '-o | --order',
        '\tIf given, all queries will be ordered after insertions.',
        '-p | --pressure',
        '\tIf given, inserted IP addresses will be condensed in a smaller range.', sep='\n')
    exit(0)


def parse_arguments() -> bool:
    state = ''
    try:
        # get path
        scripts_path = os.path.dirname(sys.argv[0])
        Config.path = os.path.normpath(os.path.join(scripts_path, '..'))
        # parse arguments
        for v in sys.argv[1:]:
            if state == '':
                if v == '-i':
                    state = 'i'
                elif v == '-q':
                    state = 'q'
                elif v == '-m':
                    state = 'm'
                elif v == '-o' or v == '--order':
                    Config.order = True
                elif v == '-p' or v == '--pressure':
                    Config.pressure = True
                else:
                    return False
            elif state == 'i':
                Config.insertion_count = int(v)
                if Config.insertion_count < 0:
                    return False
                state = ''
            elif state == 'q':
                Config.query_count = int(v)
                if Config.query_count < 0:
                    return False
                state = ''
            elif state == 'm':
                Config.miss_rate = float(v)
                if not 0 <= Config.miss_rate <= 1:
                    return False
                state = ''
        return state == ''
    except (ValueError):
        return False


if __name__ == '__main__':
    # 检验功能用
    # Entry._test()

    if not parse_arguments():
        wrong_usage_exit()

    operations = ['i'] * Config.insertion_count + ['q'] * Config.query_count
    if not Config.order:
        random.shuffle(operations)

    output = b''
    for op in operations:
        if op == 'i':
            output += Entry.insert()
        else:
            output += Entry.query()

    print('\033[31mEOF\033[0m')
    output += b'\xff\xff\xff\xff' + bytearray(12)

    open(os.path.join(Config.path, 'routing_test.data'), 'wb').write(output)
