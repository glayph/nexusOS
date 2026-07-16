# Nexus OS Customization Guide

এই ফোল্ডারের ফাইলগুলো পরিবর্তন করে তুমি Nexus OS কে নিজের মতো বানাতে পারবে।
ISO build করার আগে এখানে তোমার পরিবর্তন করো।

---

## 📦 Extra Packages — `packages.list`

```
# প্রতিটি লাইনে একটি package নাম লেখো
# # দিয়ে comment করা যাবে

# Example:
# git
# neofetch
# htop
```

Build করার সময় এই package গুলো rootfs-এ automatically install হবে।

---

## 🚀 Custom Startup Script — `startup.sh`

এই script টি প্রতিবার boot হওয়ার পর, Nexus shell চালু হওয়ার আগে run হবে।

```bash
#!/bin/bash
# কোনো service চালু করো
# systemctl start myservice
echo "Custom startup complete!"
```

---

## 🖥️ Custom MOTD — `motd.txt`

Boot-এর পর যে welcome message দেখাবে সেটা পরিবর্তন করতে পারবে।

---

## 🔧 Build করো

```bash
# Dependencies install করো (একবারই)
sudo bash install-deps.sh

# Build করো
make build

# Customize করে আবার build করো (rootfs রেখে দেয়)
make build FAST=1

# সম্পূর্ণ নতুন build
make build CLEAN=1
```
