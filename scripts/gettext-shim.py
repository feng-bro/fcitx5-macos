#!/usr/bin/python3
import pathlib
import sys


def value_after(args, option):
    for index, arg in enumerate(args):
        if arg == option and index + 1 < len(args):
            return args[index + 1]
        if arg.startswith(option + "="):
            return arg.split("=", 1)[1]
    return None


def main():
    args = sys.argv[1:]
    output = value_after(args, "-o")
    template = value_after(args, "--template")

    if output:
        out = pathlib.Path(output)
        out.parent.mkdir(parents=True, exist_ok=True)
        if template:
            out.write_bytes(pathlib.Path(template).read_bytes())
        else:
            out.write_bytes(b"")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
