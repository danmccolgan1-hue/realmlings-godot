# Running a Realmlings server on DigitalOcean

A dedicated server is a copy of the game with no window and no nation of its own. It runs on a rented computer
(a DigitalOcean "Droplet"), keeps the game's clock for everyone, and stays up when players leave. Nobody has to open
ports on their home router.

- **The first player to join hosts the game.** They choose the island and the computer nations, or a saved game to
  carry on. They can set a password, start the game, save it, and decide what happens when a player drops out. If
  they leave, the next player to have joined hosts instead.
- **Passwords are optional.** The host sets one in the lobby. You can also give the server one when it starts, so
  that even the first player needs it (otherwise a stranger who finds the address could join first and host).
- **The game is saved every minute of play.** After a crash, or a restart of the server, the lobby offers the
  interrupted game again, and each player picks their nation from it.
- **The host can save** from the in-game menu (Esc), **and load** a saved game in the lobby: either one kept on the
  server, or the last multiplayer game on the host's own computer (it is sent to the server).
- **A game ends when no player is left in it** (30 seconds after the last one leaves, so a dropped connection can
  come back), or when no player's nation is left standing. The server keeps a last save of the finished game and
  opens a fresh lobby by itself (0.19.3; there is no "End the game" button any more).
- **Observers** (0.19.3): **Watch** instead of **Join** joins without a nation. Observers see the whole map and a
  window with every player's ping, resources, army power and provinces. They never host or hold the game up, and
  don't count as players (a game with only observers left ends).
- **Host online** (0.19.3) in the Multiplayer menu asks every server on the Droplet (ports 24565-24569) whether its
  lobby is empty and joins a random empty one as its host. Ports with no server running simply don't answer.

Code: `scripts/net/mp_server.gd` (the server), `scripts/net/mp_setup.gd` (starting games and the saves folder, shared
with a player hosting from their own copy), `tests/test_server.gd`.

## What it needs

A full 8-nation map uses about 240 MB of memory and a small part of one processor: it ran 21 times faster than
real time on one core. DigitalOcean's **Basic, Regular, 1 GiB / 1 vCPU** Droplet is enough. Choose 2 GiB if you
want spare room for very long games. Traffic is tiny, because only the players' orders travel.

On your PC you need Godot 4.7.2 and PowerShell, which comes with `ssh` and `scp` on Windows 10 and 11.

## 1. Export the two builds

1. In Godot: **Editor → Manage Export Templates → Download and Install** (once, for 4.7.2).
2. **Project → Export**, choose **Linux Server**, untick **Export With Debug**, then **Export Project**. It goes to
   `build/server/Realmlings.x86_64`.
3. Choose **Windows Desktop** and export it too. That `Realmlings.exe` is what you send your friends.

Every player needs the build made from the same version as the server: the game turns away anyone whose version
differs.

## 2. Make an SSH key (once)

The key lets your PC log in to the Droplet without a password. In PowerShell:

```powershell
ssh-keygen -t ed25519            # press Enter at every question
Get-Content $HOME\.ssh\id_ed25519.pub | Set-Clipboard   # the public half, ready to paste
```

## 3. Create the Droplet

In the DigitalOcean control panel: **Create → Droplets**.

- **Region:** the one nearest most of your players, for example New York for the east of the US. Every order waits
  for the server, so a nearby one feels quicker.
- **Image:** Ubuntu 24.04 (LTS) x64.
- **Size:** Basic → Regular → 1 GiB / 1 vCPU.
- **Authentication:** SSH Key → **New SSH Key**, paste the key from step 2.
- **Hostname:** `realmlings`.

Create it and copy its **IPv4 address**: it is the address your friends join.

## 4. Open the game's port

**Networking → Firewalls → Create Firewall**, with these inbound rules:

| Type | Protocol | Port | Sources |
|---|---|---|---|
| SSH | TCP | 22 | All IPv4, All IPv6 (or only your home address) |
| Custom | UDP | 24565 | All IPv4, All IPv6 |

Leave the outbound rules as they are, apply the firewall to the `realmlings` Droplet, and create it.

## 5. Put the server on the Droplet

In PowerShell, from the project folder (replace `203.0.113.10` with your Droplet's address):

```powershell
ssh root@203.0.113.10 "adduser --system --group --home /home/realmlings realmlings; mkdir -p /home/realmlings/server /home/realmlings/saves"
scp build\server\Realmlings.x86_64 root@203.0.113.10:/home/realmlings/server/
scp tools\server\realmlings.service root@203.0.113.10:/etc/systemd/system/
ssh root@203.0.113.10 "chmod +x /home/realmlings/server/Realmlings.x86_64; chown -R realmlings: /home/realmlings; systemctl daemon-reload; systemctl enable --now realmlings"
```

The server runs as its own user, `realmlings`, not as the administrator.

**Optional: a password from the start.** On the Droplet, run `nano /etc/systemd/system/realmlings.service`, add
`--password=yourword` to the end of the `ExecStart` line, save, then run
`systemctl daemon-reload && systemctl restart realmlings`.

## 6. Check it is running

```powershell
ssh root@203.0.113.10 "systemctl status realmlings --no-pager"
ssh root@203.0.113.10 "journalctl -u realmlings -f"      # its messages as they come; Ctrl+C to stop watching
```

The first line should read `Realmlings server 0.19.3: listening on UDP port 24565`. Joins, departures, starts and
saves appear below it. A longer log is on the Droplet at
`/home/realmlings/.local/share/godot/app_userdata/Realmlings/mp_log.txt`.

## 7. Play

1. One player presses **Host online**: the game finds an empty lobby on the Droplet and shows its address and port.
   Everyone else opens **Multiplayer** and types that address (with the port, e.g. `157.245.250.30:24566`) under
   **Join by address**, plus the password, if there is one. **Watch** joins as an observer.
2. The first to join is the host. Everyone else chooses their nation under **Your Nation** and presses **Ready**.
3. The host chooses **Map Settings** (or **Load a saved game**), sets a **Password** if they want one, and presses
   **Start Game** once everyone is ready. One player may start alone. Each new lobby starts on a new random island. The host can **Remove** a player
   from the lobby: that player can't join the same lobby again under the same name. **Allows Debug** (off unless
   the host switches it on) lets every player use Settings → Debug in the game. Revealing the map and +2000
   resources then go to every player; Every technology goes to the player who presses it, in the Magic school they
   choose.
4. **Loading a saved game:** each player picks one of its nations in the lobby. Players whose names match are offered
   the nation they played. Someone has to take the first nation (the original host's), because it can't be handed to
   the computer. Nations nobody picks are played by the computer.
5. **During the game:** the host saves with **Esc → Save the game on the server**. When a player drops out, the host is
   asked whether to wait for them or hand their nation to the computer. A player who comes back joins with the same
   name. A newcomer may take a nation whose player is away.
6. **Ending:** when every player has left (observers don't count), the game is over: the server keeps a last save,
   tells any observers and opens a fresh lobby.

## Several games at once

One server runs one game. To let several groups play at the same time, run more servers on the same Droplet, each
on its own port with its own saves. Players type the port after the address: `157.245.250.30:24566`. The first
server keeps port 24565, so its players type just the address.

1. In the DigitalOcean firewall, change the game's rule to the port range **24565-24569** (UDP).
2. In PowerShell, from the project folder (replace the address):

```powershell
scp tools\server\realmlings@.service root@157.245.250.30:/etc/systemd/system/
ssh root@157.245.250.30 "systemctl daemon-reload; systemctl enable --now realmlings@24566 realmlings@24567"
```

That adds two more servers (24566 and 24567). Each uses about 200-250 MB of memory: a 1 GiB Droplet runs about
three games at once, a 2 GiB one about seven. `update_server.ps1` updates and restarts all of them.

Hosting on your own computer (**Host locally** in the Multiplayer menu) is a separate thing: your PC runs
the game and you play in it. To play on the Droplet, everyone uses **Join by address** instead.

## 8. The next game

Nothing to do: after every game the server exits with code 75, which the service treats as "start me again", and
a fresh, empty lobby is ready a few seconds later (so **Host online** finds it free). A finished game is kept in the
saves folder; the host can carry it on with **Load a saved game**. A server that crashed comes back the same way and
offers the interrupted game again.

## Updating to a new version

Export both builds again (step 1), then in PowerShell from the project folder:

```powershell
.\tools\server\update_server.ps1 -Ip 203.0.113.10
```

It uploads the new server, restarts it and shows its status. Send your friends the new `Realmlings.exe`. Updating in
the middle of a game is fine: the lobby offers the autosave again. A save made by an older version may not load in a
much newer one, though.

## Saves on the server

They are in `/home/realmlings/saves` on the Droplet. `autosave.json` is the game in progress. The `game-<date>.json`
files are the host's saves and the finished games, and each `.txt` beside one describes it. To keep a copy on your
PC:

```powershell
scp root@203.0.113.10:/home/realmlings/saves/*.json .\server-saves\
```

## Costs

A Basic Droplet is billed for as long as it exists, even while it is switched off. When you are done playtesting for
a while, keep your saves (above) and **destroy** the Droplet to stop the charges; you can make a new one later in a
few minutes.

## When something goes wrong

- **Nobody can connect:** check that the firewall has the UDP 24565 rule and is applied to the Droplet, and that
  `systemctl status realmlings` says *active (running)*.
- **"Different game versions":** that player has an older or newer `Realmlings.exe` than the server.
- **The server won't start** (`systemctl status` shows *failed*): run `journalctl -u realmlings -n 50` and send me what
  it says.
- **A player keeps dropping out:** compare their `mp_log.txt` (shown under **Connection trouble?** in the lobby) with
  the server's.
