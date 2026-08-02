#!/bin/bash

while true; do
    echo "=============================="
    echo "   Termux Pkg Manager 1.0"
    echo "=============================="
    echo "[1] Install a Package"
    echo "[2] Uninstall a Package"
    echo "[3] Update All Packages"
    echo "[4] Autoremove Cleanup"
    echo "[0] Exit"
    echo -n "Choose an option: "
    read choice

    case $choice in
        1)
            echo -n "Enter package name to install: "
            read pkg_name
            pkg install "$pkg_name"
            ;;
        2)
            echo -n "Enter package name to uninstall: "
            read pkg_name
            pkg uninstall "$pkg_name"
            ;;
        3)
            pkg upgrade
            ;;
        4)
            apt autoremove
            ;;
        0)
            echo "Catch ya later!"
            break
            ;;
        *)
            echo "Invalid option, try again."
            ;;
    esac
    echo ""
done

