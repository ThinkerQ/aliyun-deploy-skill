# ECS 运维快查表

> 运行任何命令前先 `source scripts/load-env.sh`（自动读 .env.acr/.env.ecs），再 `source scripts/ecs.sh` 注册 ecs_cmd/ecs_upload 函数。

## SSH 登录
```bash
# 由 ecs.sh 加载私钥或通过环境变量提供密码，不将密码写入临时脚本。
source scripts/load-env.sh
source scripts/ecs.sh
ecs_cmd "ls /opt/xinya"
```

## 容器操作
```bash
ecs_cmd "docker ps"                         # 列出容器
ecs_cmd "docker logs c-xinya-app --tail=100"  # 后端日志
ecs_cmd "docker restart c-xinya-app"          # 重启单容器
ecs_cmd "cd /opt/xinya/docker && \
         docker compose --env-file /opt/xinya/.env restart xinya-app"
```

## 文件操作
```bash
# 上传（本地 → ECS）
ecs_upload local_file.txt /opt/xinya/

# 下载（ECS → 本地）
ecs_download /opt/xinya/backup/xinya_hours-20260717.sql.gz ./

# 流式 grep
ecs_cmd "grep -r error /opt/xinya/docker/"
```

## MySQL
```bash
# 进 mysql CLI
ecs_mysql
# 调试时一次性 SQL
bash scripts/exec.sh mysql "SELECT user_id,user_name FROM sys_user"

# 统计当前配置数据库中的表
ecs_mysql -e 'SELECT COUNT(*) FROM information_schema.tables WHERE TABLE_SCHEMA = DATABASE();'
```

## Redis
```bash
bash scripts/exec.sh redis 'INFO memory'   # 内存使用
bash scripts/exec.sh redis 'DBSIZE'         # key 数量
```

## 备份与恢复
```bash
# 立即备份
bash scripts/backup-now.sh

# 看最近备份
ecs_cmd "ls -lh /opt/xinya/backup/"

# 在 ECS 上恢复某次备份（先 down 卷）
ecs_cmd "cd /opt/xinya/docker && \
         docker compose --env-file /opt/xinya/.env down -v && \
         docker compose --env-file /opt/xinya/.env up -d"

# 灌入 dump（不重建表）
# 预先在 ECS 配置仅所有者可读的 MySQL 客户端凭据文件。
ecs_cmd "gunzip -c /opt/xinya/backup/xinya_hours-XXX.sql.gz |
    docker exec -i c-xinya-mysql mysql --defaults-extra-file=/run/secrets/mysql-client.cnf"
```

## systemd / cron
```bash
ecs_cmd "systemctl status xinya"      # 栈状态
ecs_cmd "systemctl restart xinya"     # 重启整个栈
ecs_cmd "systemctl daemon-reload && systemctl enable xinya.service"
ecs_cmd "cat /etc/cron.d/xinya-backup && systemctl status crond"
ecs_cmd "tail /var/log/xinya-backup.log"
```

## 公网调试
```bash
# 浏览器直接看
curl -I http://${ECS_HOST}/
curl -s "http://${ECS_HOST}/prod-api/captchaImage" | head -c 100

# 本地端口转发远程 debug
ssh -L 13306:localhost:3306 -L 16379:localhost:6379 root@${ECS_HOST}
# 此时本机 localhost:13306 就是 ECS 的 MySQL
```
