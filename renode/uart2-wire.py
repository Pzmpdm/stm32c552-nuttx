# SPDX-License-Identifier: Apache-2.0
# Character-level probe and optional TX-to-RX wire for USART2.
# Data always comes from the guest's TDR writes. No canned responses.

_uart2_wire = None


def mc_uart2_install():
    global _uart2_wire
    uart = self.Machine['sysbus.usart2']
    state = {'uart': uart, 'bytes': [], 'loopback': False}

    def transmitted(value):
        state['bytes'].append(int(value))
        if state['loopback']:
            uart.WriteChar(value)

    uart.CharReceived += transmitted
    state['handler'] = transmitted
    _uart2_wire = state


def mc_uart2_clear():
    _uart2_wire['bytes'] = []


def mc_uart2_loopback(enabled):
    _uart2_wire['loopback'] = bool(int(enabled))


def mc_uart2_feed(offset, count, seed):
    uart = _uart2_wire['uart']
    for index in range(int(offset), int(offset) + int(count)):
        uart.WriteChar((index * 73 + (index // 256) * 29 + int(seed)) & 0xff)


def mc_uart2_check(count, seed):
    actual = _uart2_wire['bytes']
    expected = [(index * 73 + (index // 256) * 29 + int(seed)) & 0xff
                for index in range(int(count))]
    if actual == expected:
        print('UART2_BYTES_OK %d' % len(actual))
    else:
        first = next((i for i, pair in enumerate(zip(actual, expected))
                      if pair[0] != pair[1]), min(len(actual), len(expected)))
        print('UART2_BYTES_FAIL received=%d expected=%d first_offset=%d'
              % (len(actual), len(expected), first))
