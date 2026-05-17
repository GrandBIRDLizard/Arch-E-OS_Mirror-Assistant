# GUI for Arch & EOS Update Assistant
### By GrandBIRDLizard

---

## OVERVIEW

This setup provides a user-friendly GUI frontend for maintaining:
- Arch Linux mirrors
- EndeavourOS mirrors

It is built on top of two existing backend scripts:

1. `/usr/local/bin/update_all_mirrors_weekly.sh`
   - non-interactive
   - root-only
   - safe for automation
   - updates Arch + EndeavourOS mirrorlists
   - writes status/logging info
   - intended as the canonical backend worker

2. `/usr/local/bin/update_all_mirrors_prompt_upgrade.sh`
   - interactive CLI fallback
   - root-only
   - useful for terminal/manual fallback or debugging

The GUI layer does NOT replace these backend scripts.
It adds user-friendly wrappers for KDE Plasma.

---

## WHAT THIS INSTALLS

The installer creates these user-owned files:

1. Manual guided GUI wrapper
   `~/.local/bin/update_all_mirrors_guided_gui.sh`

---

### Purpose:
- Launch manually from Plasma or terminal
- Uses KDialog prompts
- Can open Arch News / EndeavourOS forum in Firefox
- Refreshes mirrors
- Optionally offers pacman -Syyu
- Shows reboot guidance after upgrade

2. Weekly login GUI wrapper
   `~/.local/bin/update_all_mirrors_login_gui.sh`

Purpose:
- Runs automatically when the user logs into Plasma
- Checks if mirrors were already refreshed this ISO week
- If not, runs the backend worker once
- Sends a desktop notification on success/failure
- Does NOT auto-upgrade packages
- Quietly exits if already done this week

3.  User systemd service
   `~/.config/systemd/user/update-all-mirrors-login-gui.service`

Purpose:
- Starts the weekly login GUI wrapper at graphical login

Plasma app launcher (.desktop file):
   `~/.local/share/applications/update-all-mirrors-guided.desktop`

Purpose:
- Adds a menu entry in Plasma:
"Arch & EOS Mirror Assistant"

---

## REQUIRED BACKEND SCRIPTS

These MUST already exist before running the installer:
- `/usr/local/bin/update_all_mirrors_weekly.sh`
- `/usr/local/bin/update_all_mirrors_prompt_upgrade.sh`

The GUI wrappers depend on the weekly worker directly.
The CLI prompt script remains a fallback path.

---

## AUTH / PRIVILEGE MODEL

There are TWO privilege flows:

1. Manual GUI (user launches it)

The manual GUI uses:
- pkexec

Why:
- best for GUI privilege escalation
- integrates with polkit
- good for KDE Plasma / Wayland
- correct for a menu-launched GUI app

Used for:
- mirror refresh backend call
- optional pacman -Syyu

2. Weekly login GUI (auto-run at login)

The weekly login GUI uses:
- `sudo /usr/local/bin/update_all_mirrors_weekly.sh`

Why:
- avoids a polkit / password popup during login
- runs silently once per week
- better UX than pkexec at login

IMPORTANT:
This requires an EXACT sudoers rule.

---

## REQUIRED SUDOERS RULE

Run:

  sudo visudo

Add EXACTLY:

-  `YOURUSERNSME ALL=(root) NOPASSWD: /usr/local/bin/update_all_mirrors_weekly.sh`

Example:

-  `jmoney ALL=(root) NOPASSWD: /usr/local/bin/update_all_mirrors_weekly.sh`

This allows ONLY that exact backend worker script to run without a password.

It does NOT grant general passwordless sudo.

---

## INSTALLATION

1. Ensure backend scripts already exist:

`/usr/local/bin/update_all_mirrors_weekly.sh`
`/usr/local/bin/update_all_mirrors_prompt_upgrade.sh`

2. Add the exact sudoers rule (see above)

3. Make the installer executable:

- `chmod +x install_mirror_update_gui.sh`

4.  Run the installer as the NORMAL USER (not root):

- `./install_mirror_update_gui.sh`

The installer will:

- create GUI wrapper scripts
- create the user systemd login service
- create the Plasma .desktop launcher
- enable the weekly login user service

---

## AFTER INSTALL

You should have:

Manual GUI:
-  `~/.local/bin/update_all_mirrors_guided_gui.sh`

Weekly login GUI:
-  `~/.local/bin/update_all_mirrors_login_gui.sh`

User service:
-  `~/.config/systemd/user/update-all-mirrors-login-gui.service`

Desktop launcher:
- Arch & EOS Mirror Assistant

---

## MANUAL USAGE

You can launch the manual GUI in two ways:

1. From Plasma app launcher:
- Arch & EOS Mirror Assistant

2. From terminal:
- `~/.local/bin/update_all_mirrors_guided_gui.sh`

Manual GUI flow:

- Shows reminder about manual intervention notices
- Offers quick open in Firefox for:
  - Arch Linux News
  - EndeavourOS News / Forum
- Asks if you want to refresh mirrors
- Runs backend mirror refresh
- On success, asks if you want to run:
  `pacman -Syyu`
- If you choose yes:
  - optionally offers to open the news pages again
  - runs pacman -Syyu via pkexec
- Shows reboot guidance afterward

---

## WEEKLY LOGIN BEHAVIOR

At Plasma graphical login:

- the user systemd service runs
- the login GUI wrapper checks the current ISO week
- if mirrors already refreshed this week:
  - it exits quietly
- if not refreshed this week:
  - it runs the backend worker once
  - it sends a desktop notification:
    - success
    - or failure

This means:

- it does NOT run constantly
- it does NOT run every login if already done this week
- it only refreshes once per ISO week per user state stamp

---

## WHERE WEEKLY STATE IS TRACKED

The weekly login wrapper stores its user-side state in:

- `~/.local/state/update-all-mirrors/`

Important files:

1. `last_run_week`

- stores the last ISO week that completed successfully

 `last_run.log`

- logs attempts / success / failure lines

Example use:

- `cat ~/.local/state/update-all-mirrors/last_run_week`
- `cat ~/.local/state/update-all-mirrors/last_run.log`

---

## WHERE BACKEND STATUS IS TRACKED

The root backend worker stores its status in:

- `/var/lib/update-all-mirrors-weekly/last_run.status`

This is useful for confirming:

- last successful run
- failure state
- last known backend result

Example:

- `cat /var/lib/update-all-mirrors-weekly/last_run.status`

---

## TESTING RECOMMENDATIONS

Recommended initial tests on a Plasma Wayland machine:

1) Test the backend worker directly
------------------------------------------------------------

Run:

  ```bash
  sudo /usr/local/bin/update_all_mirrors_weekly.sh
  ```

Confirm:
- mirrors update successfully
- backup files rotate
- status file is written:
  `/var/lib/update-all-mirrors-weekly/last_run.status`


2) Test the manual GUI wrapper
------------------------------------------------------------

Run:


```bash
  ~/.local/bin/update_all_mirrors_guided_gui.sh
  ```

Confirm:
- KDialog opens
- Firefox launch menu works
- pkexec prompt appears normally
- backend worker completes
- optional pacman -Syyu prompt works


3) Test the login service manually
------------------------------------------------------------

Run:


```bash
systemctl --user start update-all-mirrors-login-gui.
ervice
  ```  

Confirm:
- no password prompt (if sudoers rule is correct)
- mirror refresh runs
- desktop notification appears
- state file updates:
 ` ~/.local/state/update-all-mirrors/last_run_week`


4) Test actual login behavior
------------------------------------------------------------

Log out and back in to Plasma.

Confirm:
- if current week already ran:
  - service exits quietly
- if week changed (or state file removed):
  - service runs again


### HOW TO FORCE A RE-TEST OF WEEKLY LOGIN

If you want to simulate "not run yet this week", remove the user week stamp:

```bash  
rm -f ~/.local/state/update-all-mirrors/last_run_week
```
Then run:

```bash
systemctl --user start update-all-mirrors-login-gui.se
vice
```

This forces the wrapper to treat the week as not yet completed.


### KNOWN EXPECTED BEHAVIOR


1) The manual GUI may show a polkit / auth prompt
   - this is normal
   - it uses pkexec intentionally

2) The weekly login wrapper should NOT prompt for a password
   - if it does, the sudoers rule is missing or wrong

3) The weekly login wrapper does NOT auto-upgrade packages
   - it only refreshes mirrors

4) The manual GUI DOES offer package upgrade
   - only after mirrors refresh successfully
   - and only if the user explicitly says yes


WHY pacman -Syyu IS OFFERED AFTER MIRROR CHANGES


After changing mirrors, using:

  pacman -Syyu

is recommended because:

- -yy forces a full sync database refresh
- this ensures package metadata is refreshed against the NEW mirrors
- helps avoid stale metadata / partial-sync edge cases

This is especially useful immediately after changing mirrorlists.


## REBOOT GUIDANCE

A reboot is NOT always required after pacman -Syyu.

A reboot is recommended if the upgrade included:

- kernel packages
- microcode (amd-ucode / intel-ucode)
- systemd / glibc
- nvidia or other kernel module / graphics stack updates

## WAYLAND / KDE PLASMA NOTES


This design is intended for KDE Plasma and works well on Wayland.

Why it should behave well:

- KDialog is native to KDE / Qt environments
- pkexec is appropriate for GUI privilege escalation
- notify-send works in user session notification flow
- the login service is a user systemd service tied to graphical session

For testing on an older machine:

- This utility is lightweight
- It should run fine on modest hardware
- It does not need 3D-heavy performance
- A trimmed Plasma 6 Wayland setup should be more than enough

If Plasma Wayland is stable enough on the test box generally,
this utility should be trivial for it.


UNINSTALL

make the uninstall script executable:

```bash
chmod +x uninstall_mirror_update_gui_for_dave.sh
```
Run:

```bash
./uninstall_mirror_update_gui_for_dave.sh
```

This removes:

- `~/.local/bin/update_all_mirrors_guided_gui.sh`
- `~/.local/bin/update_all_mirrors_login_gui.sh`
- `~/.config/systemd/user/update-all-mirrors-login-gui.service`
- `~/.local/share/applications/update-all-mirrors-guided.desktop`

It does NOT remove:

- `/usr/local/bin/update_all_mirrors_weekly.sh`
- `/usr/local/bin/update_all_mirrors_prompt_upgrade.sh`

Optional cleanup after uninstall:
- remove the sudoers rule if you no longer want silent weekly login runs


## TROUBLESHOOTING


### Manual GUI opens but fails immediately


Check:

  command -v kdialog
  command -v pkexec
  command -v firefox


### Manual GUI cannot elevate / pkexec fails


Check:
- polkit is installed
- Plasma session is running normally
- pkexec exists:

  command -v pkexec


### Weekly login wrapper prompts for password


The sudoers rule is missing or incorrect.

Check with:

  sudo -l

Make sure the exact allowed command is:

`/usr/local/bin/update_all_mirrors_weekly.sh`

Weekly login wrapper does not notify

Check:

```bash
command -v notify-send
```
Also confirm the service was started inside the user graphical session.

---

### Weekly login wrapper did not run

Check user service status:
 
```bash 
systemctl --user status update-all-mirrors-login-gui.service
```

Check logs:

```bash
journalctl --user -u update-all-mirrors-login-gui.service -n 100
```
Check state files:

```bash
ls -l ~/.local/state/update-all-mirrors/
```
---

### Backend worker failed

Check:

```bash
cat /var/lib/update-all-mirrors-weekly/last_run.status
```

Also try direct backend test:

```bash
sudo /usr/local/bin/update_all_mirrors_weekly.sh
```
---

## SUMMARY

This setup gives you:

- a safe root backend worker for mirror refresh
- a terminal fallback script for manual CLI use
- a polished manual KDialog GUI
- a Plasma launcher entry
- a weekly-on-login user systemd automation path
- notifications when the weekly job actually runs

It is intentionally split so that:

- backend logic stays simple and reliable
- GUI logic stays user-friendly
- automation stays quiet and predictable
- privilege escalation is appropriate for each path

### End of README
