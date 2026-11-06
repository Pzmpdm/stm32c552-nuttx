#!/usr/bin/env python3
"""Check 100 consecutive NSH commands on a connected UART."""

import argparse
from pathlib import Path

import serial


PROMPT = b"nsh> "
BANNER = b"NuttShell (NSH)"


def read_prompt(port, log):
    response = port.read_until(PROMPT)
    log.write(response)
    log.flush()
    if not response.endswith(PROMPT):
        raise RuntimeError("timed out waiting for the NSH prompt")
    return response


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("port", help="Serial device, such as /dev/cu.usbserial-1234")
    parser.add_argument("log", type=Path, help="Path for the raw UART transcript")
    args = parser.parse_args()

    try:
        with serial.serial_for_url(
            args.port, baudrate=115200, timeout=3, write_timeout=3
        ) as port, args.log.open("xb") as log:
            port.reset_input_buffer()
            port.write(b"\r")
            read_prompt(port, log)

            for sequence in range(1, 101):
                marker = f"hw-nsh-{sequence:03d}".encode("ascii")
                port.write(b"echo " + marker + b"\r")
                response = read_prompt(port, log)
                if BANNER in response or response.splitlines().count(marker) != 1:
                    raise RuntimeError(f"unexpected response to command {sequence}: {response!r}")
    except (OSError, RuntimeError) as error:
        parser.exit(1, f"{parser.prog}: {error}\n")

    print(f"100 commands passed. UART transcript saved to {args.log}.")


if __name__ == "__main__":
    main()
