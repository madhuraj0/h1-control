# Probe scripts

macOS Swift scripts used to work out the Studio H1's control protocol. Each one opens the headphones'
serial-port channel with IOBluetooth and sends or listens for frames. Several of them **write settings**
to the headphones; read the script before running it.

```bash
export H1_ADDRESS=aa-bb-cc-dd-ee-ff   # your headphones' Bluetooth address (System Settings › Bluetooth)
swiftc -O probe2.swift -o /tmp/probe2 && /tmp/probe2 1
```

The headphones allow one control connection at a time: quit H1 Control on the Mac and phone first.
