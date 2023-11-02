# Linux Shell Scripts

一Some Linux Scripts

```sh
$ tree
├── kcptun
│   └── kcptun.sh # kcptun 一one-click installation script
└── ovz-bbr
    └── ovz-bbr-installer.sh # OpenVZ BBR 一one-click instillation script
```

## Kcptun 一one-click installation script

* Installation Command：

```sh
wget --no-check-certificate -O kcptun.sh https://github.com/AGPT-3/cyboys-shell-scripts/raw/master/kcptun/kcptun.sh
sh kcptun.sh
```

* Help Information

```sh
# sh kcptun.sh help
Please use: kcptun.sh <option>

Available parameters <option> include:

    install          Install
    uninstall        Uninstall
    update           Check for Updates
    manual           Customized Kcptun version installation
    help             View script usage instructions
    add              Add an instance, multi-port acceleration
    reconfig <id>    Reconfigure the instance
    show <id>        Displays detailed configuration of the instance
    log <id>         Display instance log
    del <id>         Deletes an instance

Note: the <id> in the above parameters is optional and represents the ID of the instance.
     You can use 1, 2, 3... to correspond to the instances kcptun, kcptun2, kcptun3... respectively.
     If <id> is not specified, it defaults to 1

Supervisor command:
    service supervisord {start|stop|restart|status}
                        
Kcptun related commands:
    supervisorctl {start|stop|restart|status} kcptun<id>

```

## OpenVZ BBR 一one-click instillation script

* Installation command：

```sh
wget --no-check-certificate -O ovz-bbr-installer.sh https://github.com/AGPT-3/cyboys-shell-scripts/raw/master/ovz-bbr/ovz-bbr-installer.sh
sh ovz-bbr-installer.sh
```

* Uninstall Command

```sh
sh ovz-bbr-installer.sh uninstall
```
