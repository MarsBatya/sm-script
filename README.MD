# Service Manager (sm)

[![License: MIT](https://img.shields.io/badge/License-MIT-darkgreen?style=for-the-badge&labelColor=black)](LICENSE)
![CLI Tool](https://img.shields.io/badge/CLI-Tool-darkgreen?style=for-the-badge&labelColor=black)
![Linux](https://img.shields.io/badge/Linux-black?style=for-the-badge&logo=linux&logoColor=green)
![Bash](https://img.shields.io/badge/Bash-121011?style=for-the-badge&logo=gnubash&logoColor=green)
![systemd](https://img.shields.io/badge/systemd-black?style=for-the-badge)

A lightweight wrapper around **systemctl** and **journalctl** for easier project management.

---

## 🚀 Installation

Requires Linux with `systemd`, `bash`, and `sudo` access.

```bash
git clone https://github.com/MarsBatya/sm-script.git
cd sm-script
sudo ln -s "$PWD/sm" /usr/local/bin/sm && sudo chmod +x "$PWD/sm"
```

Keep the cloned directory around — `sm update` (see below) pulls updates into it, and
`sm install-helpers` sources scripts from it.

---

## ✅ Verify Installation

```bash
sm help
```

---

## 📖 Usage

### Project Management

* `sm add`
  Add project from the current directory.

* `sm start [project_name] [--no-enable] [--skip-verify]`
  Start a project and enable it at boot (infers name from `.service` file if not provided).
  Pass `--no-enable` to start it without changing its enabled/disabled state.

* `sm restart [project_name] [--skip-verify]`
  Restart a project without touching its enabled/disabled state (infers name from `.service` file if not provided).

  Both `start` and `restart` first run `systemd-analyze verify` against the unit file systemd would actually
  load (the installed copy in `/etc/systemd/system`, falling back to sm's local copy if that isn't readable),
  so a bad directive (e.g. an `ExecStart` binary that doesn't exist) is reported clearly up front instead of
  only showing up afterwards as "Failed to start service, use `sm logs`". A hard validation error blocks the
  start/restart; pass `--skip-verify` to bypass the check and proceed anyway.

* `sm stop [project_name] [--disable]`
  Stop a project (infers name from `.service` file if not provided). By default the service stays enabled
  and will start again on the next boot; pass `--disable` to also disable it.

* `sm remove [project_name]` (alias: `sm rm`)
  Remove a project (infers name from `.service` file if not provided). If the project was added with
  "add to sm management only" (see `sm add` below), sm never installed its unit file and won't delete it.

* `sm info [project_name]`
  Show important info about a project (infers name from `.service` file if not provided).

* `sm ls` (alias: `sm list`)
  List all projects.

* `sm update`
  Pull the latest changes into the cloned `sm` repository (`git pull origin master`).
  Requires that `sm` was installed by symlinking from a git clone (see Installation).

---

### Logs & Directories

* `sm logs [project_name] [-n|--lines N] [-f|--follow | --no-follow] [-s|--since WHEN]`
  Show project logs (infers name from `.service` file if not provided).
  Follows the log by default (`-f`); pass `--no-follow` to just print and exit.
  `-n`/`--lines` caps the number of lines shown (default 100).
  `-s`/`--since` filters by start time and accepts shorthand alongside anything `journalctl --since` understands:
  relative (`30m`, `1h`, `2d`, `1w`) or absolute (`26.02.26`, `26.02.2026`, `26.02.26 14:30`).

  ```bash
  sm logs myapp -s 1h              # everything from the last hour, following
  sm logs myapp -s 2d -n 50        # last 50 lines since 2 days ago
  sm logs myapp --no-follow -n 20  # last 20 lines, no follow
  ```

* `sm workdir <project_name>`
  Echo the project folder path. Unlike most other commands, this requires an explicit `project_name` —
  it does not infer it from a `.service` file in the current directory.

* `sm dive <project_name>` (alias: `sm cd`)
  Dive into a project folder. Also requires an explicit `project_name`.
  *(make sure to run `sm install-helpers` once beforehand).*

---

### Helpers

* `sm install-helpers`
  Install tab completion and enable `sm dive` in your `~/.bashrc`.
  ⚠️ Bash only — it edits `~/.bashrc`. zsh/fish users won't get completion or `sm dive`
  from this command and need to source `sm-completion.sh` / `sm-wrapper-for-dive.sh` manually.

* `sm help`
  Show the help message.

* `sm uninstall`
  Unlink sm and clean up any changed or added files.

---

## ⚡ Quickstart Example

```bash
# 1. Add the project (from inside project directory with a .service file)
sm add

# 2. Start the service
sm start

# 3. Check logs in real-time
sm logs

# 4. Dive into the project folder (project name is required, e.g. the name from step 1)
sm dive myapp

# 5. Show info
sm info

# 6. Stop and remove the service when done
sm stop
sm remove
```

---

## ℹ️ Notes

* Commands that accept `[project_name]` (shown in brackets) will automatically infer the project name
  from `.service` files in the current directory if no name is provided. `workdir` and `dive` are the
  exceptions — they take `<project_name>` and always require it explicitly.

---

## 📜 License

This project is licensed under the [MIT License](LICENSE).

