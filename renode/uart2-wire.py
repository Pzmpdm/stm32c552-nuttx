# SPDX-License-Identifier: Apache-2.0
# Character-level probe and optional TX-to-RX wire for USART2.
# Data comes from the guest's TDR writes. Loopback delivers one 8N1 frame
# per 115200-baud frame interval in virtual time.

from collections import deque
from System import Action

_uart2_wire = None


def mc_uart2_install():
    global _uart2_wire
    uart = self.Machine['sysbus.usart2']
    state = {'uart': uart, 'bytes': [], 'loopback': False, 'pending': deque()}

    def transmitted(value):
        state['bytes'].append(int(value))
        if state['loopback']:
            state['pending'].append(value)

    def deliver():
        if state['pending']:
            uart.WriteChar(state['pending'].popleft())

    state['delivery'] = self.Machine.ObtainManagedThread(Action(deliver), 11520)
    uart.CharReceived += transmitted
    state['handler'] = transmitted
    _uart2_wire = state


def mc_uart2_clear():
    _uart2_wire['bytes'] = []
    _uart2_wire['pending'].clear()


def mc_uart2_loopback(enabled):
    state = _uart2_wire
    state['loopback'] = bool(int(enabled))
    if state['loopback']:
        state['delivery'].Start()
    else:
        state['delivery'].Stop()


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
