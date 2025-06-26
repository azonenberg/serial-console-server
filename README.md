# serial-console-server
Bare metal UART to SSH console server. Fast, no OS, no fluff.

Early WIP, still doing high level design so far

## Sysadmin / end user perspective

* Scalable design with 1 to 4 line cards
* Can buy base chassis with one line card and populate more as demands scale
* Possible line card options:
  * 8x RS232 w/ hardware FC on Cisco-compatible RJ45
  * Maybe LVCMOS33 UART?
  * 32x LVCMOS33 GPIO on 0.1" pin headers
* May offer smaller (non-rackmount) enclosure versions that cost less but can only fit 1/2 line cards
* Management access
  * SSH CLI on TCP 22, allows configuring IP address, DHCP/DNS, NTP for timestamping logs, etc, plus port config
  * SFTP for OTA firmware update (copy ELF binary to /dev/mcu or FPGA bitstream to /dev/fpga)
  * aes128-gcm / ssh-ed25519 cipher suite only (hardware accelerated)
* UART access:
  * SSH to TCP 2200 + interface index
  * Optional (disabled by default, can switch on per port): raw TCP on TCP 3000 + interface index
* Optional 4 kB per port history buffer (when you reconnect, last N bytes are replayed)
* Role based access control
  * Can have arbitrarily many roles, default one (admin)
  * Each username is assigned to exactly one role
  * Each username has one or more ssh-ed25519 public keys
  * Attributes of role:
    * System admin (can add/remove keys, change network config, etc)
    * Port N admin (can enable/disable FC, change baud rate, assign nickname, enable/disable history, read/write)
    * Port N user (can read/write)
    * Port N monitor (can read but not write)
    * TODO: figure out perms for GPIOs

## Mechanical form factor

* 1U partial-width (size TBD, may vary depending on how many line cards we support)
* Very shallow chassis, 100mm or less ideally, intended for rear mounting in a 4-post rack
  * Tentative concept: 3D printed ESD CF-PLA body with laser cut PMMA face plate and ears
* All ports on rack-facing side
* Indicator LEDs and e-ink status display on aisle-facing side
* No fans, passive cooling

* Logic board: OSHPark 6 layer? Or try to go multech even with tariffs, to get better price per board if we make a bunch?
* Line card: nothing special, 4L 2S2P
* Back panel: indicator LEDs, can probably even be 2L

## Architecture notes

* USB-C powered, TDP <5W
* Artix-7 FTG256 most likely, has 170 GPIOs (3 full + 1 partial bank)
  * Partial bank for RGMII?
  * One full bank for MCU I/F
  * 2 banks for UART

## FPGA resource usage estimates

Need to build a full RTL skeleton to validate, this is synth only
* Curve25519: 7425 LUT, 1409 LUTRAM, 5740 DFF, 32 DSP, about 35% of a 7a35t
* We might need to go to the 50t or something to have all these bells and whistles? Lol
So far seems like fitting everything in a 35t in ftg256 might be doable?
