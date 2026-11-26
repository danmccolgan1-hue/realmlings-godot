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
- **The server stops when the game ends**: when the host ends it from the in-game menu, or when no player's nation is
  left standing. It keeps a last save of the finished game. Start it again for the next game (step 8).

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

The first line should read `Realmlings server 0.19.0: listening on UDP port 24565`. Joins, departures, starts and
saves appear below it. A longer log is on the Droplet at
`/home/realmlings/.local/share/godot/app_userdata/Realmlings/mp_log.txt`.

## 7. Play

1. Everyone opens **Multiplayer** and types the Droplet's address under **Join by address**, plus the password, if
   there is one.
2. The first to join is the host. Everyone else chooses their nation under **Your Nation** and presses **Ready**.
3. The host chooses **Map Settings** (or **Load a saved game**), sets a **Password** if they want one, and presses
   **Start Game** once everyone is ready. On a server, one player may start alone. The host can **Remove** a player
   from the lobby: that player can't join the same lobby again under the same name.
4. **Loading a saved game:** each player picks one of its nations in the lobby. Players whose names match are offered
   the nation they played. Someone has to take the first nation (the original host's), because it can't be handed to
   the computer. Nations nobody picks are played by the computer.
5. **During the game:** the host saves with **Esc → Save the game on the server**. When a player drops out, the host is
   asked whether to wait for them or hand their nation to the computer. A player who comes back joins with the same
   name. A newcomer may take a nation whose player is away.
6. **Ending:** the host uses **Esc → End the game for everyone**. The server saves the game, tells everyone and stops.

## 8. The next game

The server stays stopped after a game ends, so start it again:

```powershell
ssh root@203.0.113.10 "systemctl start realmlings"
```

If you would rather it reopened the lobby by itself after every game, change `Restart=on-failure` to `Restart=always`
in the service file, then run `systemctl daemon-reload`.

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
