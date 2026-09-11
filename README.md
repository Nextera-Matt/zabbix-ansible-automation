<div align="center">

# 📡 Zabbix Ansible Automation

**Consolidated Ansible automation for Zabbix agent deployment — cloud-ready, firewall-aware, and built to replace hours of manual onboarding with minutes.**

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg?style=for-the-badge)](LICENSE)
[![Ansible](https://img.shields.io/badge/Ansible-EE0000?style=for-the-badge&logo=ansible&logoColor=white)](https://www.ansible.com/)
[![Zabbix](https://img.shields.io/badge/Zabbix-CC2936?style=for-the-badge&logo=zabbix&logoColor=white)](https://www.zabbix.com/)

[Features](#-features) • [Usage](#-usage) • [How It Works](#-how-it-works)

</div>

---

## ⚠️ The Problem

| Challenge | Impact |
|-----------|--------|
| 🕐 **Manual onboarding** | 1–2 hours per server, every time |
| 🧩 **Fragmented scripts** | Legacy automation scattered across 3 directories with duplicate YAML |
| ☁️ **Poor cloud support** | Non-standard SSH users and key auth broke the old playbooks |
| 🔥 **No firewall awareness** | Operators had to know each customer's firewall setup by hand |

## ✨ The Solution

```
one-command onboarding
        │
        ▼
detect OS + cloud platform ──▶ detect firewall (CSF → iptables → nftables → firewalld → UFW)
        │
        ▼
install + configure Zabbix agent ──▶ register host + assign templates
        │
        ▼
verify connectivity
```

## 🚀 Features

- ✅ **Cloud-ready** — non-root SSH users (rocky, ubuntu, debian, centos, cloud-user, almalinux), key-based auth, automatic sudo escalation
- 🔥 **Firewall auto-detection** — priority-ordered across CSF, iptables, nftables, firewalld, and UFW, with rich-rules support
- 🔄 **Full host lifecycle** — deployment and safe interactive removal (API-only or full removal)
- 📝 **Audit trail** — every action logged

## 📋 Requirements

```
✓ Ansible 2.14+
✓ SSH access to target hosts
✓ Zabbix server with API access
```

## 🎮 Usage

```bash
git clone https://github.com/Nextera-Matt/zabbix-ansible-automation.git
cd zabbix-ansible-automation/zabbix_ansible_modernised
./zabbixsetup.sh
```

The setup script walks through target selection, auth method, and firewall handling interactively.

## 🔄 How It Works

Onboarding took 1–2 hours per server and broke constantly on modern OSes. This rebuild brought it down to about 5 minutes, validated across 500+ deployments with zero failures on supported platforms.

## 🛠️ Stack

<p align="center">
  <img src="https://img.shields.io/badge/Ansible-EE0000?style=for-the-badge&logo=ansible&logoColor=white" />
  <img src="https://img.shields.io/badge/Bash-4EAA25?style=for-the-badge&logo=gnubash&logoColor=white" />
  <img src="https://img.shields.io/badge/Zabbix-CC2936?style=for-the-badge&logo=zabbix&logoColor=white" />
  <img src="https://img.shields.io/badge/Linux-FCC624?style=for-the-badge&logo=linux&logoColor=black" />
</p>

## 📄 License

This project is licensed under the MIT License — see the [LICENSE](LICENSE) file.

## 📬 Support

<div align="center">

[![GitHub Issues](https://img.shields.io/github/issues/Nextera-Matt/zabbix-ansible-automation)](https://github.com/Nextera-Matt/zabbix-ansible-automation/issues)

[Open an Issue](https://github.com/Nextera-Matt/zabbix-ansible-automation/issues) • [Visit Portfolio](https://matthodges.uk)

</div>

---

<div align="center">

**Made by [Matt Hodges](https://matthodges.uk)**

</div>
