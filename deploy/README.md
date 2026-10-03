# 部署（Ansible + ansible-vault）

参照 soulvy（cider）的部署方案：控制机把 CI 构建好的 release 包推到服务器，
Ansible 负责校验、解压、迁移、切软链、健康检查，失败自动回滚。
敏感参数全部用 `ansible-vault` 加密，密文 `deploy/vault.yml` 可安全提交到 git。

## 文件说明

| 文件 | 作用 | 是否提交 |
| --- | --- | --- |
| `ansible.cfg` | 指定 vault 密码文件、inventory、SSH 保活参数 | 是 |
| `inventory.ini` | 目标主机分组（`writing`） | 是 |
| `vars.yml` | 非敏感部署配置，引用 vault 变量 | 是 |
| `vault.yml` | **加密**的密钥（`ansible-vault`） | 是（密文） |
| `vault.yml.example` | 明文模板，照着填 `vault.local.yml` | 是 |
| `vault.local.yml` | 明文工作副本，填完加密成 `vault.yml` | **否**（已 gitignore） |
| `.vault_pass` | vault 解密密码 | **否**（已 gitignore） |
| `deploy.yml` | 部署 playbook | 是 |
| `templates/env.sh.j2` | 渲染 `/opt/writing/env.sh`（0600） | 是 |
| `templates/writing.service.j2` | 渲染 systemd unit | 是 |
| `release-assets/` | 待部署的 tarball + SHA256SUMS | **否**（已 gitignore） |

配套代码（不在本目录）：
- `lib/writing/release.ex` — `Writing.Release.migrate/0`，供 playbook 跑迁移
- `rel/overlays/bin/server` — systemd `ExecStart` 用的启动脚本
- `.github/workflows/release.yml` — 构建 + 发布 release + 调 playbook 部署

## 一次性配置

### 1. 生成加密的 vault.yml

```sh
cp deploy/vault.yml.example deploy/vault.local.yml
$EDITOR deploy/vault.local.yml      # 填 vault_database_url / vault_secret_key_base 等
ansible-vault encrypt deploy/vault.local.yml --output deploy/vault.yml
git add deploy/vault.yml            # 只提交密文
```

`vault_secret_key_base` 用 `mix phx.gen.secret` 生成。
`vault_wechat_appid` / `vault_wechat_secret` 可从项目根目录 `.env` 拷贝；
留空不影响 Elixir 应用启动，只是 `scripts/*.py` 没法调微信接口。

### 2. 本地写 vault 密码

```sh
echo '你的密码' > deploy/.vault_pass
chmod 600 deploy/.vault_pass
```

### 3. 配置 GitHub Actions 密钥

```sh
gh secret set VAULT_PASS --repo jerry-chao/writing         # 与上面同一个密码
gh secret set DEPLOY_SSH_KEY --repo jerry-chao/writing < ~/.ssh/id_ed25519
```

## 部署

推荐用 CI（会在同一个 job 里构建 release 并直接部署）：

```sh
gh workflow run release.yml --repo jerry-chao/writing      # 默认 deploy=true
gh workflow run release.yml -f deploy=false --repo jerry-chao/writing   # 只发 release 不部署
```

本地手动部署（需自备 release 包）：

```sh
# 1. 准备 release-assets/
gh release download <version> --repo jerry-chao/writing --dir deploy/release-assets

# 2. 部署
cd deploy
ansible-playbook deploy.yml -i inventory.ini -e "release_version=<version>"
```

## 部署流程

1. 校验 `release_version` 格式，拒绝空值 / 路径分隔符 / `..`
2. 记录当前 `current` 软链指向（用于回滚）
3. 校验 release 资产存在，把 tarball 与 `SHA256SUMS` 传到服务器
4. **服务器上校验 SHA256**，不匹配立即失败
5. 解压到 `/opt/writing/releases/<version>/`
6. 渲染 `env.sh`（0600）与 systemd unit
7. 跑 `Writing.Release.migrate()`（切软链**之前**，此时旧版本还持有连接池）
8. 原子切换 `current` 软链 → 重启服务 → `systemctl is-active` → HTTP 健康检查
9. 任何一步失败：把 `current` 软链切回旧版本并重启，然后报错退出

服务器上最终结构：

```
/opt/writing/
├── env.sh                     # 0600，密钥都在这里
├── current -> releases/<ver>  # 软链，systemd 的 WorkingDirectory
└── releases/<ver>/
```

## 注意

- `deploy/ansible.cfg` 里 `vault_password_file = .vault_pass` 是**相对路径**，
  所以必须在 `deploy/` 目录内执行 `ansible-playbook`。
- SSH 用户是 `ubuntu`（免密 sudo），playbook 靠 `become: true` 提权。
- `config/prod.exs` 的 `force_ssl` 排除了 `127.0.0.1`，所以健康检查走
  `http://127.0.0.1:4006/` 不会被重定向到 HTTPS。
- `priv/static/assets/` 和 `cache_manifest.json` 都被 gitignore，
  所以 CI 里必须先 `mix compile`（生成 colocated 资源）再 `mix assets.deploy`。
