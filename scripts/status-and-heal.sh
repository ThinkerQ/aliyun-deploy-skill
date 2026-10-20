# ============================================================
#  xinya.service ——  systemd 单元（开机自启 docker compose 栈）
# ============================================================
#  安装：
#     sudo cp xinya.service /etc/systemd/system/
#     sudo systemctl daemon-reload
#     sudo systemctl enable xinya.service
# ============================================================

[Unit]
Description=Xinya Ruoyi Docker Compose Stack
Documentation=https://github.com/your-org/xinya_ry
Requires=docker.service
After=docker.service network-online.target
Wants=network-online.target

[Service]
Type=oneshot
WorkingDirectory=/opt/xinya/docker
EnvironmentFile=-/opt/xinya/.env
ExecStart=/usr/bin/docker compose up -d
ExecStop=/usr/bin/docker compose down
ExecReload=/usr/bin/docker compose restart
RemainAfterExit=yes
TimeoutStartSec=300

[Install]
WantedBy=multi-user.target
