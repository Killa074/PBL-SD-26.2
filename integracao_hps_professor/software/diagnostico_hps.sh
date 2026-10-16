#!/bin/sh
# Read-only inventory: no devmem, bridge writes, FPGA programming or SD changes.
printf '\n=== Kernel ===\n'
uname -a
printf '\n=== Linux ===\n'
if [ -r /etc/os-release ]; then cat /etc/os-release; else printf '/etc/os-release ausente\n'; fi
printf '\n=== Modelo ===\n'
if [ -r /proc/device-tree/model ]; then tr '\000' '\n' < /proc/device-tree/model; else printf 'device-tree/model ausente\n'; fi
printf '\n=== Pontes FPGA (somente leitura) ===\n'
if [ -d /sys/class/fpga_bridge ]; then
 for bridge in /sys/class/fpga_bridge/*; do
  [ -d "$bridge" ] || continue
  printf '%s\n' "$bridge"
  for field in name state; do
   if [ -r "$bridge/$field" ]; then printf '%s: ' "$field"; cat "$bridge/$field"; fi
  done
 done
else printf '/sys/class/fpga_bridge ausente nesta imagem\n'; fi
printf '\n=== Ferramentas ===\n'
command -v gcc || true
command -v make || true
printf '\nNenhuma configuracao foi alterada. Envie esta saida junto com o texto do boot.\n'
