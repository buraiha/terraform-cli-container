# Terraform CLI コンテナ運用

ホストへ Terraform / Azure CLI をインストールせず、必要なときだけコンテナを起動する運用キットです。macOS、Linux、Windows + WSL2 の Bash / Zsh から利用できます。標準は Podman、Docker へも切り替えられます。Azure CLI と Terraform を同じイメージに入れるため、Terraform の Azure CLI 認証がコンテナ内で完結します。

## 構成と保存先

| 対象 | 保存先 |
| --- | --- |
| ホスト側コマンド | `~/.local/bin/tfbox`、`tf`、`tfaz`（コピーされた実体） |
| ビルド定義 | `${XDG_DATA_HOME:-$HOME/.local/share}/terraform-cli-container` |
| CLI本体 | ローカルイメージ `localhost/terraform-cli:1.7.5` |
| Azure認証 | 名前付きボリューム `terraform-cli-azure` |
| Terraform定義、state、plan、lock | コマンドを実行したホストのカレントディレクトリ |
| SSH公開鍵 | 指定した `.pub` だけ読み取り専用マウント |
| 実行コンテナ | コマンド終了時に `--rm` で削除 |

Terraform 1.7.5 は参照元と合わせた互換性重視の初期値で、最新版という意味ではありません。Azure CLI は `2.77.0-azurelinux3.0` に固定しています。既存stateを開く前に、そのプロジェクトの `required_version`、既存実行バージョン、provider lock を確認してください。CLIの運用キットとインフラ定義は別リポジトリで管理します。

## 1. 準備・ビルド

Git と稼働中の Podman または Docker が必要です。macOS の Podman は既存マシンを `podman machine start` で起動してください。Windows はWSL2内へcloneし、WSLからコンテナランタイムが使える状態にします。ファイルはWSLのLinux側（例 `~/src`）へ置くと権限や性能の問題を避けやすくなります。

```bash
git clone https://github.com/buraiha/terraform-cli-container.git
cd terraform-cli-container
./bin/install.sh
export PATH="$HOME/.local/bin:$PATH"
tfbox build
tf version
tfaz version

# Dockerの場合はビルド前から指定する
# export TFBOX_RUNTIME=docker
```

amd64 / arm64 をビルド先のアーキテクチャから自動判定します。HashiCorpの配布ZIPを同じ配布元のSHA256一覧と照合します。これは破損検知であり、独立した署名検証ではありません。ビルドコンテキストにはContainerfileだけを送ります。

## 2. インストール後の運用

`bin/install.sh`は`tfbox`、`tf`、`tfaz`の実行ファイルを標準で`~/.local/bin`にコピーし、Containerfileと`.dockerignore`を`~/.local/share/terraform-cli-container`（XDG_DATA_HOME設定時はその配下）へ保存します。**インストール後はcloneしたリポジトリを削除しても、実行・再ビルドできます。** 削除は任意で、自動削除しません。

`tf`は`tfbox tf`、`tfaz`は`tfbox az`を呼びます。シェル関数やclone先を指す`TFBOX_HOME`は不要です。旧方式で定義した`tf`・`tfaz`関数はシェル設定から削除し、新しいターミナルで利用してください。現在のBash/zshでは`unset -f tf tfaz`でも解除できます。

PATHを永続化する場合は`export PATH="$HOME/.local/bin:$PATH"`を`~/.bashrc`や`~/.zshrc`等へ一度だけ追加します。

- `TFBOX_BIN_DIR`: インストール先。標準`~/.local/bin`。
- `TFBOX_DATA_DIR`: ビルド定義のインストール先・実行時の参照先。標準`${XDG_DATA_HOME:-$HOME/.local/share}/terraform-cli-container`。変更する場合はビルド実行時にも同じ値を指定してください。

更新は再clone、または残したclone先で`git pull --ff-only`してから`./bin/install.sh`を再実行します。管理対象の旧版はインストール先の`.terraform-cli-container-backup.*`へ退避し、無関係な既存コマンド・データは上書きしません。コンテナイメージの更新は別途`tfbox build`が必要です。

アンインストール時は管理対象を確認し、インストールした3コマンドとビルド定義ディレクトリを取り除きます。コンテナイメージ、認証ボリューム、プロジェクトのstateは残ります。

## 3. Azureへログイン

```bash
tfaz login --use-device-code
tfaz account list --output table
tfaz account set --subscription '<対象のサブスクリプションID>'
tfaz account show --output table
export ARM_SUBSCRIPTION_ID='<対象のサブスクリプションID>'
```

ブラウザで表示されたURLとコードを入力してサインインします。認証キャッシュはこのCLIキット専用のボリュームに保存します。ホストの `~/.azure` を共有しません。期限切れなら再ログインしてください。`az` 操作には作業ディレクトリをマウントしません。

環境を分ける場合は、認証する前に `export TFBOX_AZURE_VOLUME=terraform-cli-azure-dev` など別の名前を指定します。同じボリューム内の `account set` は共有されるため、複数のサブスクリプションを同時に操作する場合も分けてください。

## 4. Terraformプロジェクトを操作

CLIキットではなく、対象の `.tf` があるディレクトリへ移動します。

```bash
cd /path/to/terraform-project
# 必要なプロジェクトのみ。秘密鍵は渡さない。
export TFBOX_SSH_PUBLIC_KEY="$HOME/.ssh/id_ed25519_azure_prd.pub"

tf init
tf fmt -check
tf validate
tf plan -out=change.tfplan
tf show change.tfplan
# 内容を確認した後に、利用者が実行する
tf apply change.tfplan
tf output
```

公開鍵はホストと同じ絶対パスでマウントされます。`.tf` の公開鍵パスと一致させてください。既存定義にMac固定パスがある場合は、WSL側の公開鍵パスへ変数で設定します。`file("~/.ssh/...")` や `pathexpand` はコンテナのHOMEを指すため使わず、絶対パスを設定してください。

`/work` は実行時の `$PWD` だけです。親ディレクトリを参照するローカルmoduleはマウント外になるため、共通の親へ移動して `tf -chdir=環境ディレクトリ init` などを使います。SELinux環境はホスト側のラベル設定も確認してください。

Linux / WSLではホストUID/GIDで実行します。Podmanでは `keep-id` も指定します。認証ボリュームの所有者は実行UIDに合わせます。同一ボリュームを異なるUIDで同時利用しないでください。macOSはPodman/DockerのVMを通して利用します。

## state・秘密情報・Git

各インフラプロジェクトにも本リポジトリの `.gitignore` 相当を設定してください。state、plan、tfvars、認証キャッシュ、秘密鍵はコミットしません。`.terraform.lock.hcl` はコミットし、provider更新は内容をレビューします。

ローカルstateはホストに残り、コンテナ削除では消えません。複数端末・複数人で運用する場合は、Azure Storage等のロックに対応するremote backendを別途設定し、同時applyを避けます。このキットはbackendやクラウドリソースを作成しません。stateやplanには秘密値が入ることがあるので、バックアップとアクセス権を適切に管理してください。

必要な場合だけ、`ARM_SUBSCRIPTION_ID`、`ARM_TENANT_ID`、`ARM_CLIENT_ID`、`ARM_CLIENT_SECRET`、`ARM_USE_OIDC`、`ARM_OIDC_TOKEN`、`ARM_USE_AZUREAD` をホスト環境から引き継ぎます。値をファイルへ書き出しません。`TF_VAR_*` やAWS等の環境変数は自動転送しません。対話ログインでは不要なサービスプリンシパル変数をunsetしてください。

## 削除・ログアウト

削除操作は利用者が対象を確認して実施します。

```bash
tf plan -destroy -out=destroy.tfplan
tf show destroy.tfplan
# 削除対象を確認した後だけ実行
tf apply destroy.tfplan

tfaz logout
```

`logout` 後もボリュームは残ります。不要になった専用ボリュームのみ、利用者が `podman volume rm terraform-cli-azure`（Dockerなら `docker volume rm`）で削除できます。

## バージョン更新・診断

```bash
# プロジェクトと互換性を確認した具体的な版を指定
export TFBOX_TF_VERSION='<更新先のバージョン>'
export TFBOX_IMAGE="localhost/terraform-cli:$TFBOX_TF_VERSION"
tfbox build
tf version
# 必要ならコンテナ内の調査シェル
tfbox shell
```

Azure CLIの更新はContainerfileのFROMを変更して再ビルドします。各種タグはバージョン固定ですがdigest固定ではありません。完全に同じベースを要求する運用では確認済みdigestも固定してください。

接続できない場合はランタイムの起動、WSL連携、`TFBOX_RUNTIME` を確認します。認証エラーは `tfaz account show` と対象subscriptionを確認します。TTYは対話端末時だけ自動付与するので、CIでも同じラッパーを使用できます。CIは対話認証ではなく、別途OIDC等の認証設定が必要です。

## 検証

`bash tests/wrapper.sh`と`bash tests/install.sh` で引数、空白入りパス、マウント、非TTY実行、実体コピー・再インストール・clone先削除後の起動とビルドを検証します。GitHub Actions用の設定例は`docs/github-actions-verify.yml`に保存しています。Dockerでのビルド、CLI起動、クラウド接続不要の`init`・`validate`・`plan`を行う内容で、apply / destroyは行いません。今回のGit認証にはworkflow更新権限がないため、自動CIは未設定です。有効化する場合は必要なGitHub権限でこのファイルを`.github/workflows/verify.yml`へ配置してください。

### 2026-10-29のローカル確認

macOS arm64 + Podmanで、隔離したユーザー領域にインストールした後、配布元を削除して`tf version`（1.7.5）、`tfaz version`（Azure CLI 2.77.0）、保存済みContainerfileによる`tfbox build`を確認しました。クラウドへ接続しない最小構成の`init`・`validate`・`plan`も確認済みです。実際のAzureログイン・apply・destroyは行っていません。Docker/WSL2/Linuxでの実機検証は未実施で、自動CIは未設定です。

## 参照

- [Azure CLI公式コンテナ](https://learn.microsoft.com/cli/azure/run-azure-cli-docker)
- [Terraform CLI](https://developer.hashicorp.com/terraform/cli)
- [AzureRM providerのAzure CLI認証](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/guides/azure_cli)
