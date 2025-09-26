# Service Manager (sm) - A lightweight wrapper around systemctl and journalctl

### installing:
```bash
sudo ln -s $PWD/sm /usr/local/bin/sm && sudo chmod +x $PWD/sm
```

### verifying installation:
```bash
sm help
```


Usage:

  `sm add`                        - Add project from current directory

  `sm start [project_name]`       - Start a project (infers name from .service file if not provided)

  `sm stop [project_name]`        - Stop a project (infers name from .service file if not provided)

  `sm logs [project_name]`        - Show project logs (infers name from .service file if not provided)

  `sm ls`                         - List all projects

  `sm remove [project_name]`      - Remove a project (infers name from .service file if not provided)

  `sm help`                       - Show this help message

  `sm install-completion`         - Install tab completion for "sm"

Note: Commands that accept [project_name] will automatically infer the project name from .service files in the current directory if no name is provided.
