# 排错手册

## §1 docker login 报 `unauthorized: authentication required`

**症状**：`docker login registry.cn-hangzhou.aliyuncs.com -u ${ALIYUN_ACCOUNT_ID} --password-stdin` 401。

**原因**：ACR 个人版 login 的 username 必须是 **阿里云主账号邮箱**，不是 11 位账号 ID。

**修复**：用 `${ACR_USER}`（你自己的主账号邮箱）+ 访问凭证里"固定登录密码"。详见 `references/architecture.md §1`。

---

## §2 `Bind for 0.0.0.0:80: address already in use`

**症状**：`docker compose up` 时 c-xinya-web 反复 `Restarting`，日志里 `bind: address already in use`，且 ECS 上 `ss -tlnp | grep :80` 能看到 nginx 占着。

**修复**：
```bash
ecs_cmd "systemctl stop nginx && systemctl disable nginx"
bash scripts/release.sh    # 重启 stack
```

> ECS 镜像默认带 `nginx.service`，如不需要可在 `bash scripts/deploy-new.sh` 里自动停掉。

---

## §3 web 容器 `host not found in upstream "xinya-app"`

**症状**：`docker logs c-xinya-web | grep -E 'emerg|host not found'` 输出：
```
host not found in upstream "xinya-app" in /etc/nginx/conf.d/default.conf:42
```

**原因**：`/etc/nginx/conf.d/default.conf` 写的是 `xinya-app`（service 名），但 compose 文件里 service 名错写成了 `c-xinya-app`。

**修复**：把 `docker-compose.cloud.yml` 里 web 与 app 服务的 service 名保持 `xinya-app` / `xinya-web`（不带 `c-`），容器名才用 `c-xinya-app` / `c-xinya-web`：

```yaml
services:
  xinya-app:                       # service 名固定（web 镜像 nginx.conf 写死这个）
    container_name: c-xinya-app    # 容器名才加 c-
```

这点是整个 skill 最容易踩的坑。

---

## §4 `Table 'xinya_hours.sys_xxx' doesn't exist`

**症状**：后端启动时 SQL 报"表不存在"。

**原因**：MySQL 镜像的 `docker-entrypoint-initdb.d/` **不递归执行子目录**。MySQL init 只看直接放在该目录下的 `.sql` 文件。

**修复**：挂载为直接文件，不要挂载子目录：
```yaml
volumes:
  - ../sql/01-schema/01-xinya_hours_schema.sql:/docker-entrypoint-initdb.d/01-schema.sql:ro
  - ../sql/02-init-data/01-xinya_hours_data.sql:/docker-entrypoint-initdb.d/02-data.sql:ro
```

文件名字母顺序要确保 `01-` 先于 `02-`，否则数据 INSERT 会先于表创建。

---

## §5 MySQL 卷残数据导致 init 跳过

**症状**：dump 文件已挂，但 `SELECT COUNT(*)` 还是 0 或表行数不对。

**原因**：MySQL 容器首次启动会执行 `initdb.d/`；如果上次失败但卷留有数据，下次启动会跳过 init。

**修复**：
```bash
ecs_cmd "cd /opt/xinya/docker && \
         docker compose --env-file /opt/xinya/.env down -v && \
         docker compose --env-file /opt/xinya/.env up -d"
```

`down -v` 删卷才会强制重新 init。

---

## §6 nginx upstream "xinya-app" 但 c-xinya-app 容器

与 §3 同根。也可在 `docker-compose.cloud.yml` 里给 web 服务加 `extra_hosts`（不推荐）或者干脆改镜像（不实际）。

最稳的方案：**service 名始终保持 `xinya-app`，container 名加 `c-` 前缀**。

---

## §7 buildx "open Dockerfile: no such file or directory"

**症状**：`docker buildx build -f Dockerfile /some/path` 失败。

**原因**：在 Git Bash + MSYS 环境下，路径转换有时会把 dockerfile 路径解析错。

**修复**：先 `cd` 到 context 目录，再写 `-f Dockerfile`：
```bash
cd D:/gitee/xinya_ry/ruoyi-ui
docker buildx build --platform linux/amd64 \
  -t registry.cn-hangzhou.aliyuncs.com/xinya/web:v1.0.0 \
  --push -f Dockerfile .
```

后端镜像：
```bash
cd D:/gitee/xinya_ry
docker buildx build --platform linux/amd64 \
  -t registry.cn-hangzhou.aliyuncs.com/xinya/app:v1.0.0 \
  --push -f ruoyi-admin/Dockerfile .
```

---

## §8 SSH Permission denied (publickey,password)

**症状**：Windows 端 `ssh` 拒绝访问。

**原因**：密码错，或 sshd 不允许 root 密码登录。

**修复**：
1. 确认 `.env.ecs` 里 `ECS_PASSWORD` 正确
2. 看 `ecs_cmd "cat /etc/ssh/sshd_config | grep -E 'PermitRoot|Password'"` —— 阿里云默认 `PermitRootLogin yes`、`PasswordAuthentication yes`，应该 OK
3. 如果之前改过 SSH 密钥方式，把 `.env.ecs` 里改成 `ECS_SSH_KEY=/path/to/key.pem`

---

## §9 Docker buildx 在 Git Bash 上 `pipe broken`

**症状**：`docker buildx build --push ... | tail` 之类的管道失败。

**修复**：单独跑 `docker buildx build --push ...`，不要 pipe。`build-and-push.sh` 与 `release.sh` 都已经避免了 pipeline。

---

## §10 镜像拉取很慢 / pull 几分钟不出

**症状**：ecs 拉 mysql 镜像等 5+ 分钟。

**修复**：`/etc/docker/daemon.json` 配 Aliyun 加速器：
```bash
ecs_cmd "mkdir -p /etc/docker
         cat > /etc/docker/daemon.json <<'EOF'
{
  \"registry-mirrors\": [\"https://YOUR_ACCOUNT_ID.mirror.aliyuncs.com\"]
}
EOF
         systemctl restart docker"
```

或者改用 skill 方式：**所有镜像（mysql/redis/app/web）都先 push 到 ACR**，ECS 只拉 ACR，不直接拉 docker.io。这正是当前实现的——`build-and-push.sh` 已经把 mysql/redis 镜像搬运到 ACR。

---

## §11 后端启动后 `GLOBAL_CACHE_DIR_NOT_PERMITTED`（Quartz 报错）

**症状**：日志频繁出现 `GLOBAL_CACHE_DIR_NOT_PERMITTED`，但应用还活着。

**原因**：Quartz scheduler 默认在 `/tmp/` 写文件，新版 Java security 限制默认拒绝。

**修复**：当前部署可忽略（不影响功能）。如果想干净，加 JVM 参数 `-Dorg.quartz.threadPool.class=org.quartz.simpl.SimpleThreadPool` 或在 `/opt/xinya/.env` 里给 `JAVA_TOOL_OPTIONS` 加 `-Djava.io.tmpdir=/home/ruoyi/quartztmp`。

---

## §12 浏览器 502 Bad Gateway

**症状**：访问 `http://<ECS_IP>/` 出现 nginx 502。

**原因 1**：c-xinya-app 没启动或没 healthy。
**原因 2**：nginx upstream `xinya-app` 解析失败（见 §3）。

**修复**：
```bash
bash scripts/diagnose.sh
bash scripts/logs.sh SERVICE=xinya-app
bash scripts/logs.sh SERVICE=xinya-web
```

---

## §13 "Messages from broker cannot be handled" / Druid 异常

**症状**：Druid 监控页面无数据。

**修复**：访问 `http://<ECS_IP>/prod-api/druid/`，账号 `ruoyi` / `123456`。前端 nginx `/prod-api/` 应该代到 `c-xinya-app:8080/druid/`，但若启动时数据库连接没正常还会 500，先看 c-xinya-app 日志。

---

## §14 升级 portal 容器后，资源还在根目录（image 没换）

**症状**：
```bash
docker exec c-xinya-portal ls /usr/share/nginx/html/
# 看到的是 index.html、styles.css、main.js、assets/（v1.0.0 旧版）
# 而不是预期的 portal/index.html、portal/styles.css、...（v1.0.1 新版）
```

**原因**：本地改了 `ruoyi-ui/portal/Dockerfile`（如 COPY 路径变了），新镜像 `portal:v1.0.1` 推到 ACR 了，但 ECS 上的 `docker-compose.yml` 里 xinya-portal 服务的 image 字段还是 `portal:v1.0.0`。`docker compose pull xinya-portal` 拉的是 v1.0.0，`up -d` 用的是 v1.0.0——新镜像完全没被使用。

**修复**：
1. **必须**先在 ECS 上改 compose 文件（不是本地）：
   ```bash
   ssh ... ecs_cmd "sed -i 's|portal:v[0-9.]*|portal:v1.0.1|' /opt/xinya/docker/docker-compose.yml"
   ```
2. 再 pull + 重建：
   ```bash
   ssh ... ecs_cmd "cd /opt/xinya/docker && \
                    docker compose --env-file /opt/xinya/.env pull xinya-portal && \
                    docker compose --env-file /opt/xinya/.env up -d xinya-portal"
   ```
3. 验证：
   ```bash
   ssh ... ecs_cmd "docker exec c-xinya-portal ls /usr/share/nginx/html/portal/ | head"
   # 应该看到 index.html、styles.css、main.js、assets/
   ```

更省事的方式：用 skill 提供的 `bash scripts/upgrade-portal.sh`（已经内置了改 compose + pull + 重建 + 健康检查四步）。

---

## §15 ECS 上 docker-compose.yml（不带 .cloud）才是实际生效文件

**症状**：本地改了 `D:/gitee/xinya_ry/docker/docker-compose.cloud.yml`（如把 portal 镜像 tag 从 v1.0.0 改成 v1.0.1），SCP 上传到 ECS `/opt/xinya/docker/docker-compose.cloud.yml`，但 `docker compose up -d` 实际用的还是 v1.0.0。

**原因**：`docker compose` 默认查找 `docker-compose.yml` 或 `docker-compose.yaml`；除非显式 `-f` 指定，否则 `.cloud.yml` 完全被忽略。

**修复**：
1. **改 ECS 上的 `/opt/xinya/docker/docker-compose.yml`**（不带 .cloud 后缀）
2. 或者用 `docker compose -f /opt/xinya/docker/docker-compose.cloud.yml ...` 显式指定（不推荐，每次命令都要带 -f）
3. `scp` 上传 `docker-compose.cloud.yml` 没有意义——可以删了

**自检**：
```bash
ssh ... ecs_cmd "cd /opt/xinya/docker && docker compose config | grep portal:0"
# 应该看到 portal 服务的 image 字段是当前想用的 tag
```

---

## §16 外层 nginx 多个 master 进程导致 reload 不彻底

**症状**：
- `nginx -t` 语法 OK，`nginx -s reload` 也跑成功
- 但 `curl ${PUBLIC_BASE_URL}/` 仍然返回旧内容（或 404）
- `ps -ef | grep 'nginx: master' | grep -v grep` 输出**多行**（正常应该 1 个 master）

**原因**：历史 `nginx -s reload` / `nginx` 命令累积，每次都拉起新的 master。`nginx -s reload` 只让最新的 master 重读配置，**其他 legacy master 还在用旧配置**响应请求。

**修复**：
```bash
# 1) 优雅停掉所有 master 与 worker
ssh ... ecs_cmd "pkill -f 'nginx: master' && pkill -f 'nginx: worker' && sleep 2"

# 2) 用 systemctl 或直接 nginx 重新拉起（外层 nginx 在 Alibaba Cloud Linux 上不一定有 systemd unit）
ssh ... ecs_cmd "nginx"
# 验证：ps -ef | grep 'nginx: master' | grep -v grep  应该只 1 行

# 3) 重新 reload 一次确保配置生效
ssh ... ecs_cmd "nginx -s reload"

# 4) 验证
ssh ... ecs_cmd "curl -sI ${PUBLIC_BASE_URL}/ -k | head -3"
```

**预防**：每次只通过 `systemctl reload nginx` 或 `nginx -s reload` 重新加载配置；不要手动 `nginx` 拉新进程。

---

## §17 浏览器访问 `/system/user` 等会员端老路径 404

**症状**：会员端登录后菜单点击 `/system/user` 正常，但**浏览器刷新**该 URL → 404。

**原因**：后端菜单数据（`sys_menu` 表）的 path 字段是绝对路径（`/system/user`），没有 `/member` 前缀。改造为会员端统一加 `/member` 前缀后，前端路由表全部用 `/member/system/...`，但**菜单管理页面没一次性更新所有菜单项**。

浏览器刷新时直接访问 `/system/user`：
- 不匹配外层 nginx 的 `/member/`、`/platform/`、`/prod-api/`、`/static/`、`/styles/`、`/html/` 等显式分流
- 命中兜底 `location /`

**修复**（两条线选一）：

**A. 一次性修复（推荐长期方案）**：
1. 登录会员端，进入"系统管理 → 菜单管理"
2. 把所有会员端菜单的 path 从 `/system/...` 改成 `/member/system/...`，从 `/education/...` 改成 `/member/education/...`，从 `/monitor/...` 改成 `/member/monitor/...`
3. 保存后让前端重新拉 `/getRouters`，菜单导航和刷新都正常

**B. 兜底走 web（已部署的临时方案）**：
- 当前外层 nginx 兜底 `location /` 已经从 portal 改为 web（见 `architecture.md §6` 第 12 条）
- 浏览器访问 `/system/user` → web 容器 `try_files $uri $uri/ /index.html` → 返回 web SPA 入口
- vue-router 客户端路由找不到 → 自动跳到 `/member/404` 友好提示页（不是 HTTP 404）
- 这是**已知限制**——业务上仍要走 A 才能彻底解决

**自检（确认兜底是否生效）**：
```bash
ssh ... ecs_cmd "curl -sI ${PUBLIC_BASE_URL}/system/user -k | head -3"
# 应返回 200（不是 404），且 body 是 web 容器的 SPA 入口
```
