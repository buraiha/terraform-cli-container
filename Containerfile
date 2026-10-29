# Managed by terraform-cli-container installer
FROM mcr.microsoft.com/azure-cli:2.77.0-azurelinux3.0
ARG TF_VERSION=1.7.5
RUN tdnf install -y curl unzip ca-certificates git openssh-clients && tdnf clean all
RUN set -eu; \
    case "$(uname -m)" in x86_64) arch=amd64 ;; aarch64|arm64) arch=arm64 ;; *) exit 1 ;; esac; \
    cd /tmp; \
    file="terraform_${TF_VERSION}_linux_${arch}.zip"; \
    curl -fsSLO "https://releases.hashicorp.com/terraform/${TF_VERSION}/${file}"; \
    curl -fsSLO "https://releases.hashicorp.com/terraform/${TF_VERSION}/terraform_${TF_VERSION}_SHA256SUMS"; \
    while read -r sum name; do if [ "$name" = "$file" ]; then printf '%s  %s\n' "$sum" "$name"; fi; done < "terraform_${TF_VERSION}_SHA256SUMS" > terraform-checksum; \
    test -s terraform-checksum; \
    sha256sum -c terraform-checksum; \
    unzip "$file" -d /usr/local/bin; \
    rm -f "$file" terraform-checksum "terraform_${TF_VERSION}_SHA256SUMS"; \
    terraform version
ENV AZURE_CONFIG_DIR=/root/.azure
WORKDIR /work
ENTRYPOINT []
CMD ["terraform", "version"]
