# frpc

wget https://raw.githubusercontent.com/tdcomcl/frpc/main/install.sh
chmod +x install.sh 

./install.sh -s frp.igromi.com -p 12000 -t token

nano /etc/frp/frpc.ini


systemctl restart frpc.service && systemctl status frpc.service 
