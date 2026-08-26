# Service Manager (sm)

[![License: MIT](https://img.shields.io/badge/License-MIT-darkgreen?style=for-the-badge&labelColor=black)](LICENSE)
![CLI Tool](https://img.shields.io/badge/CLI-Tool-darkgreen?style=for-the-badge&labelColor=black)
![Linux](https://img.shields.io/badge/Linux-black?style=for-the-badge&logo=linux&logoColor=green)
![Bash](https://img.shields.io/badge/Bash-121011?style=for-the-badge&logo=gnubash&logoColor=green)
![systemd](https://img.shields.io/badge/systemd-black?style=for-the-badge)

A lightweight wrapper around **systemctl** and **journalctl** for easier project management.

---

## 🚀 Installation

```bash
sudo ln -s $PWD/sm /usr/local/bin/sm && sudo chmod +x $PWD/sm
````

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

* `sm start [project_name] [--no-enable]`
  Start a project and enable it at boot (infers name from `.service` file if not provided).
  Pass `--no-enable` to start it without changing its enabled/disabled state.

* `sm restart [project_name]`
  Restart a project without touching its enabled/disabled state (infers name from `.service` file if not provided).

* `sm stop [project_name] [--disable]`
  Stop a project (infers name from `.service` file if not provided). By default the service stays enabled
  and will start again on the next boot; pass `--disable` to also disable it.

* `sm remove [project_name]`
  Remove a project (infers name from `.service` file if not provided). If the project was added with
  "add to sm management only" (see `sm add` below), sm never installed its unit file and won't delete it.

* `sm info [project_name]`
  Show important info about a project (infers name from `.service` file if not provided).

* `sm ls`
  List all projects.

---

### Logs & Directories

* `sm logs [project_name]`
  Show project logs (infers name from `.service` file if not provided).

* `sm workdir <project_name>`
  Echo the project folder path. Unlike most other commands, this requires an explicit `project_name` —
  it does not infer it from a `.service` file in the current directory.

* `sm dive <project_name>`
  Dive into a project folder. Also requires an explicit `project_name`.
  *(make sure to run `sm install-helpers` once beforehand).*

---

### Helpers

* `sm install-helpers`
  Install tab completion and enable `sm dive` in your `~/.bashrc`.

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

