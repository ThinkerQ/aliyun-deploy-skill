# aliyun-deploy-skill

面向阿里云 ECS 的部署与运维 Skill，配套 Bash 脚本管理基于 Docker Compose 的应用环境。
当前流程适配 xinya_ry / RuoYi 教育系统，涵盖后端、Web 前端、独立官网，以及 MySQL、Redis
等服务的日常运维。

本仓库提供 Skill 指引、操作脚本和参考文档。业务源码、Dockerfile、项目 Compose 文件、
初始化 SQL 和实际凭据需要在使用环境中另行准备。迁移到其他项目时，应先调整服务名、路径和构建流程。

## 主要能力

- 查询容器状态、资源使用、服务日志和常见故障。
- 构建与推送应用镜像，执行远程发布和版本回滚。
- 单独构建、发布和升级官网 Portal。
- 调用项目备份脚本，执行数据库查询和容器调试。
- 按需执行新环境初始化和数据重置。

## 目录说明

| 路径 | 用途 |
| --- | --- |
| [SKILL.md](SKILL.md) | Skill 入口、工作流和操作说明 |
| [scripts/](scripts/) | 配置加载、SSH 封装、发布和运维脚本 |
| [references/](references/) | 架构说明、运维快查和故障排查资料 |
| [tests/](tests/) | 本地隔离测试和凭据处理验证 |
| [evals/](evals/) | Skill 离线评估场景 |
| [.env.example](.env.example) | 可公开提交的配置示例 |
| [.gitignore](.gitignore) | 私有配置、密钥和备份的忽略规则 |

## 使用准备

本地需要 Bash、OpenSSH 和 Git；Windows 可使用 Git Bash。镜像构建需要 Docker Buildx，
目标 ECS 需要已安装 Docker 和 Docker Compose，并具备访问镜像仓库的条件。

业务项目应包含脚本所依赖的源码、Dockerfile、云端 Compose 文件、备份脚本和初始化 SQL。
使用前请结合 [架构说明](references/architecture.md) 核对当前脚本中的服务名称、
目录约定和反向代理配置，确认与目标环境一致。

如果通过支持本地 Skill 的 AI 工具使用，将此目录放入该工具的 Skill 目录，
并以 [SKILL.md](SKILL.md) 为入口。也可以在仓库根目录直接执行 Bash 脚本。

## 配置

首次使用时，在仓库根目录运行以下命令；已有 `.env` 时直接编辑，避免覆盖本地配置：

```bash
cp .env.example .env
```

仅在本地编辑 `.env` 并填写实际值。主要配置分组如下：

| 配置项 | 说明 |
| --- | --- |
| `XINYA_DOCKER_DIR` | 业务项目的 Docker 配置目录 |
| `ACR_REGISTRY`、`ACR_NAMESPACE`、`ACR_USER`、`ACR_PASSWORD` | 镜像仓库与登录凭据 |
| `ECS_HOST`、`ECS_USER` | SSH 目标与登录用户 |
| `ECS_SSH_KEY` 或 `ECS_PASSWORD` | SSH 私钥路径或登录密码；两者都设置时优先使用私钥 |
| `MYSQL_ROOT_PASSWORD`、`MYSQL_USER`、`MYSQL_PASSWORD`、`MYSQL_DATABASE` | 部署与数据库操作配置 |
| `PUBLIC_BASE_URL` | Portal 升级后的公网检查地址 |
| `ECS_PRIVATE_HOST`、`ALIYUN_ACCOUNT_ID` | 本地环境资料，按需记录 |
| `APP_ADMIN_USER`、`APP_ADMIN_PASSWORD` | 初始化后台账号记录，不负责修改应用账号 |

配置文件使用 Bash 赋值语法，包含空格或特殊字符的值需要正确引用；只加载可信文件。
默认从仓库根目录读取 `.env`，也可通过 `XINYA_ENV_FILE` 指定其他本地配置路径。
兼容读取业务项目 Docker 目录中的 `.env.acr` 和 `.env.ecs`，统一 `.env` 中的设置优先。
当前公共配置加载器会校验 ACR 和 SSH 凭据，因此状态查询也需要满足这些配置要求。

修改本地数据库密码或后台账号变量不会自动更新已有数据库、应用账号或初始化 SQL。
首次部署前，应确认这些值与业务项目 Compose 配置、应用配置及初始化 SQL 一致。

## 常用命令

在完成配置并核对目标环境后，从仓库根目录执行：

```bash
# 查询运行状态
bash scripts/status.sh

# 查看日志
bash scripts/logs.sh

# 诊断常见故障
bash scripts/diagnose.sh

# 执行应用发布入口；构建与更新范围以当前 release.sh 为准
VERSION=v1.0.1 bash scripts/release.sh

# 单独构建并升级 Portal
VERSION=v1.0.1 bash scripts/build-and-push-portal.sh
PORTAL_TAG=v1.0.1 bash scripts/upgrade-portal.sh

# 调用目标环境中的数据库备份脚本
bash scripts/backup-now.sh
```

发布、升级、回滚和备份命令会操作真实环境。新环境初始化与数据重置的详细流程见
[SKILL.md](SKILL.md)；其中数据重置会删除 MySQL / Redis 数据卷，操作前须确认目标环境、
完成备份并验证可恢复性。故障处理可参考 [排错手册](references/troubleshooting.md)。

## 本地验证

```bash
bash tests/run-all.sh
```

测试使用临时配置与 SSH / Docker 模拟，检查配置兼容性、密码传递、脚本语法和 Git 忽略规则。
安装 Docker Compose 时，还会通过本地 `config` 命令验证特殊字符配置，不连接 ECS、
不执行部署、不创建容器。该测试分支还需要可用的 Python。

## 凭据与公开提交

实际 `.env`、私钥、数据库导出和本地回滚记录已纳入忽略规则；仓库仅提交不含真实凭据的配置示例。
不要在 README、Issue、日志或截图中粘贴真实密码、访问令牌、主机地址或账号信息，
也不要使用 `git add -f` 强制提交私有配置。提交前可用 `git status --short --ignored`
确认私有 `.env` 仍处于忽略状态。

Git 忽略规则不会清除已提交的历史内容；若误提交有效凭据，应及时更换凭据并处理相关历史记录。
