# ECS 当前架构与文件位置速查

## 1. ECS 主机

| 项 | 值 |
|---|---|
| 公网 IP | `${ECS_HOST}` |
| 内网 IP | `${ECS_PRIVATE_HOST}`（eth0） |
| 操作系统 | Alibaba Cloud Linux 3（rhel/centos 兼容） |
| Docker | 26.1.3 + Compose v2.27.0 |
| 内存 | 3.5GiB |
| 系统盘 | 40GB（已用 13GB，剩 27GB） |

## 2. 容器拓扑

| 服务（service / DNS 名） | 容器名 | 镜像 | 端口（host→容器） | 资源 |
|---|---|---|---|---|
| `xinya-mysql` | `c-xinya-mysql` | `xinya/mysql:8.4` | 不暴露主机（可用 ssh 端口转发） | 1.5GB 限制内 |
| `xinya-redis` | `c-xinya-redis` | `xinya/redis:7.2-alpine` | 不暴露主机 | - |
| `xinya-app` | `c-xinya-app` | `xinya/app:v1.0.19` | 不暴露主机（由 web 反代） | mem_limit 1536M |
| `xinya-web` | `c-xinya-web` | `xinya/web:v1.0.21` | `127.0.0.1:8080:80`（仅 loopback） | - |
| `xinya-portal` | `c-xinya-portal` | `xinya/portal:v1.0.1` | `127.0.0.1:8081:80`（仅 loopback） | - |

⚠️ **service 名 ≠ container 名**：
- service 名（Docker 网络 DNS）：`xinya-app` ← nginx upstream 写死这个名字
- container 名（`docker ps` 看到）：`c-xinya-app` ← 加 `c-` 前缀避免与本地部署冲突

改 compose 文件时这点千万不能错。`docker-compose.cloud.yml` 是这么配置的，本地 `docker-compose.yml` 用的是 `xinya-app`（无 c-）。

⚠️ **web / portal 容器都只暴露到 host loopback（127.0.0.1）**——公网 80/443 由宿主机外层 nginx 1.24.0（`/etc/nginx/nginx.conf`）反代，不要把 8080/8081 直接开公网。

## 3. 数据 / 备份 / 上传 卷

| 在哪 | 干啥 |
|---|---|
| `/opt/xinya/docker/docker-compose.yml` | 云端编排主文件（**注意是 .yml 不带 .cloud 后缀**，docker compose 默认用这个） |
| `/opt/xinya/docker/docker-compose.cloud.yml` | 本地仓库里 SCP 上传过去的同名文件，**实际不生效**——别误改这个 |
| `/opt/xinya/.env` | `ACR_REGISTRY` / `ACR_NAMESPACE` / `IMAGE_TAG`（IMAGE_TAG 只控制 app/web） |
| `/opt/xinya/sql/01-schema/01-xinya_hours_schema.sql` | CREATE TABLE（68KB） |
| `/opt/xinya/sql/02-init-data/01-xinya_hours_data.sql` | INSERT 数据（109KB） |
| `/opt/xinya/uploadPath/` | 容器内 `/home/ruoyi/uploadPath` 的 bind mount |
| `/opt/xinya/backup/` | 14 天滚动 .sql.gz |
| `/opt/xinya/scripts/backup.sh` | mysqldump 脚本 |
| `/etc/systemd/system/xinya.service` | 开机自启单元 |
| `/etc/cron.d/xinya-backup` | 每日 03:00 cron 配置 |
| `/etc/nginx/nginx.conf` | 外层 nginx 路径分流（443 server 块） |

## 4. 数据库状态

- 65 张表（sys_* / qrtz_* / edu_* / system_* / 业务旧命名）
- `sys_user` 共 3 条（含 `admin`、`ry`、第三个是中文名）
- 初始化后台账号由项目 SQL 决定；本地 `.env` 的 `APP_ADMIN_*` 仅作记录，不会更改线上账号。

## 5. ACR 个人版镜像清单

```
registry.cn-hangzhou.aliyuncs.com/xinya/app:v1.0.19          （后端，由 .env IMAGE_TAG 控制）
registry.cn-hangzhou.aliyuncs.com/xinya/app:latest
registry.cn-hangzhou.aliyuncs.com/xinya/web:v1.0.21          （前端 SPA，由 .env IMAGE_TAG 控制）
registry.cn-hangzhou.aliyuncs.com/xinya/web:latest
registry.cn-hangzhou.aliyuncs.com/xinya/portal:v1.0.1        （官网主站，独立 tag，由 compose 文件 image 字段控制）
registry.cn-hangzhou.aliyuncs.com/xinya/portal:latest
registry.cn-hangzhou.aliyuncs.com/xinya/mysql:8.4
registry.cn-hangzhou.aliyuncs.com/xinya/redis:7.2-alpine
```

每次发版 push 两个 tag（新版本号 + `latest`）。mysql/redis 只在首次 setup 时 push，之后不变。**portal 单独走自己的 tag 体系**——`IMAGE_TAG` 只控制 app/web，portal 的 tag 写在 `docker-compose.yml` 里 xinya-portal 服务的 image 字段。

## 6. 外层 nginx 路径分流

`/etc/nginx/nginx.conf` 在 443 server 块内按 `location` 优先级（`=` 精确 > `^~` 前缀 > 普通 prefix > 正则）把请求分给 web（127.0.0.1:8080）或 portal（127.0.0.1:8081）。当前规则（自上而下）：

| 优先级 | location | 转给 | 用途 |
|---|---|---|---|
| 1 | `= /` | portal | 官网主站首页 |
| 2 | `= /styles.css` | portal | portal 主页引用的 CSS（精确文件） |
| 3 | `= /main.js` | portal | portal 主页引用的 JS（精确文件） |
| 4 | `/assets/` | portal | portal 静态资源（logo.svg 等） |
| 5 | `= /index.html` | web | web 容器 SPA 入口（会员端用） |
| 6 | `= /favicon.ico` / `= /favicon.svg` / `= /robots.txt` / `= /50x.html` | web | web 容器顶层静态资源 |
| 7 | `/static/` | web | webpack 输出的 JS/CSS chunks |
| 8 | `/html/` / `/styles/` / `/portal/` | web | web 容器 dist 子目录（element-ui 主题、ie.html、portal 子目录等） |
| 9 | `/member/` | web | 会员端 SPA 路径 |
| 10 | `/platform/` | web | 平台端 SPA 路径 |
| 11 | `/prod-api/` | web | 后端 API 反代（web 容器再转给 xinya-app:8080） |
| 12 | `/` | web | **兜底走 web**，让 SPA fallback 接住会员端老路径（如 `/system/user`），vue-router 找不到时跳到 `/member/404` 友好提示页 |

**为什么 portal 资源放子目录而不是根目录**：
- portal Dockerfile 把 `public/portal/` 内容 COPY 到 `/usr/share/nginx/html/portal/`（**不是根目录**）
- portal 容器 nginx.conf 的 `root` 改为 `/usr/share/nginx/html/portal`
- 这样 portal 主页（用 `./styles.css`、`./main.js`、`./assets/...` 相对路径）能被 nginx 正常服务
- 同时 web 容器 dist 根目录里的 `/static/`、`/styles/`、`/html/` 不会被外层 nginx 兜底误转到 portal

**为什么兜底走 web**：
- 后端菜单 path 是绝对路径（`/system/user`、`/education/...`），切换为 `/member/system/...` 需要在菜单管理页面人工改一次
- 在那之前，登录会员端后菜单点击走 vue-router 客户端路由没问题，但**浏览器刷新**就是直接访问 `/system/user`
- 如果兜底走 portal，会 HTTP 404
- 兜底走 web 后，web 容器 `try_files $uri $uri/ /index.html` 返回 SPA 入口，vue-router 找不到 → 跳 `/member/404` 友好提示页

修改外层 nginx 后必须先 `nginx -t` 语法检查，再 `nginx -s reload`。**坑**：ECS 上可能同时有多个 nginx master 进程（之前的 `nginx -s reload` 没杀干净的），reload 时只刷新最新一个；其他 master 还在用旧配置，导致实际响应与配置不符。检查：`ps -ef | grep 'nginx: master' | grep -v grep | wc -l`——超过 1 时需要 `pkill -f 'nginx: master' && systemctl start nginx`（或直接 `nginx` 重新拉起）。

## 7. 当前资源快照

## 7. 当前资源快照

```
NAME            CPU %    MEM USAGE / LIMIT      MEM %
c-xinya-web     0.00%    5.2MiB / 3.5GiB        0.14%
c-xinya-app     0.13%    743.1MiB / 1.5GiB      48.38%
c-xinya-mysql   0.13%    451.9MiB / 3.5GiB      12.61%
c-xinya-redis   0.07%    5.8MiB / 3.5GiB        0.16%
c-xinya-portal  0.00%    ~6MiB / 3.5GiB         0.16%  （nginx:1.27-alpine 静态站）
```

启动时间 `Started RuoYiApplication in 12.495 seconds`。
