BR=20000kbit #20M
tc qdisc replace dev wlp0s20f3 handle ffff: ingress && \
tc filter replace dev wlp0s20f3 parent ffff: protocol all prio 1 u32 \
  match u32 0 0 \
  action police rate $BR burst 32k conform-exceed drop/ok && \
tc -s qdisc show dev wlp0s20f3 && \
tc -s filter show dev wlp0s20f3 parent ffff: && \
echo "OK to STOP" && read k && \
tc qdisc del dev wlp0s20f3 ingress
