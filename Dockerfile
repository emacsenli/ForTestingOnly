FROM pytorch/pytorch:2.0.1-cuda11.7-cudnn8-runtime

ENV DEBIAN_FRONTEND=noninteractive

# 1. 更新源并安装软件
# 【重点】这里必须加上 openssh-server，否则没法配置 SSH
RUN apt-get update && apt-get install -y \
    openssh-server \
    git \
    curl \
    wget \
    tmux \
    vim \
    unzip \
    htop \
    build-essential \
    pkg-config \
    libssl-dev \
    sudo \
    # Playwright 依赖的一些基础库，虽然后面会自动装，但先装上保险
    libasound2 \
    libgbm1 \
    && rm -rf /var/lib/apt/lists/* \
    && git lfs install
    
# 2. 【核心步骤】配置 SSH 安全设置
# 这几行命令的意思是：
# - 创建 SSH 运行必须的目录
# - 使用 sed 查找配置文件里的 "PasswordAuthentication yes" 并改成 "no"
# - 同时也禁止 ChallengeResponseAuthentication
# - 允许 root 用户通过 Key 登录 (prohibit-password 意味着禁止密码但允许 Key)
RUN mkdir -p /var/run/sshd && \
    sed -i 's/#PasswordAuthentication yes/PasswordAuthentication no/g' /etc/ssh/sshd_config && \
    sed -i 's/PasswordAuthentication yes/PasswordAuthentication no/g' /etc/ssh/sshd_config && \
    sed -i 's/#PermitRootLogin prohibit-password/PermitRootLogin prohibit-password/g' /etc/ssh/sshd_config && \
    sed -i 's/PermitRootLogin yes/PermitRootLogin prohibit-password/g' /etc/ssh/sshd_config

# ==============================================================================
# 3. 安装 Rust (Stable) & Cargo
# ==============================================================================
# 设置环境变量，确保 cargo 命令全局可用
ENV RUSTUP_HOME=/usr/local/rustup \
    CARGO_HOME=/usr/local/cargo \
    PATH=/usr/local/cargo/bin:$PATH

# 下载并安装 Rust，-y 表示自动确认
RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --default-toolchain stable && \
    chmod -R a+w $RUSTUP_HOME $CARGO_HOME

# ==============================================================================
# 4. Node.js (NVM + Node LTS + PNPM)
# ==============================================================================
# 设置 NVM 目录
ENV NVM_DIR /root/.nvm
ENV NODE_VERSION lts/*

# 安装 NVM, Node.js LTS, 并安装 PNPM
# 注意：我们在同一个 RUN 指令里完成安装和环境设置，以确保生效
RUN curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.7/install.sh | bash && \
    . $NVM_DIR/nvm.sh && \
    nvm install --lts && \
    nvm alias default lts/* && \
    nvm use default && \
    npm install -g pnpm

# 【关键】将 Node 和 PNPM 添加到系统 PATH
# 这样 subsequent RUN commands 和 SSH 登录后都能直接用 node/pnpm
ENV PATH $NVM_DIR/versions/node/v20.10.0/bin:$PATH
# 注意：上面的 v20.10.0 是写示例，为了动态获取，我们用软链接技巧：
RUN ln -sf $(ls -d $NVM_DIR/versions/node/* | tail -1)/bin/node /usr/local/bin/node && \
    ln -sf $(ls -d $NVM_DIR/versions/node/* | tail -1)/bin/npm /usr/local/bin/npm && \
    ln -sf $(ls -d $NVM_DIR/versions/node/* | tail -1)/bin/pnpm /usr/local/bin/pnpm

# ==============================================================================
# 4. 安装 Neovim (最新稳定版)
# ==============================================================================
# Ubuntu apt 源里的 neovim 通常太老(v0.4)，SpaceVim 需要 v0.8+
# 这里直接从 GitHub 下载最新的编译版本
RUN wget https://github.com/neovim/neovim/releases/latest/download/nvim-linux64.tar.gz -O /tmp/nvim.tar.gz && \
    tar -C /opt -xzf /tmp/nvim.tar.gz && \
    rm /tmp/nvim.tar.gz && \
    ln -s /opt/nvim-linux64/bin/nvim /usr/local/bin/nvim && \
    # 做一个软链接，让你输 vi 或 vim 也能打开 nvim
    ln -sf /usr/local/bin/nvim /usr/local/bin/vim

# ==============================================================================
# 5. 安装 SpaceVim
# ==============================================================================
# 自动安装 SpaceVim 到 root 用户
RUN curl -sLf https://spacevim.org/install.sh | bash


# 3. 安装 uv
RUN pip install uv
# --- 创建主虚拟环境 ---
ENV VENV_PATH=/opt/venv_main
RUN uv venv $VENV_PATH

# 方便后续命令调用 python
ENV VENV_PYTHON=$VENV_PATH/bin/python
ENV VENV_PIP=$VENV_PATH/bin/pip

# --- A. 安装基础大模型工具 & Playwright ---
# huggingface_hub[cli] 包含了 hf_transfer 加速下载
# playwright 安装库
RUN $VENV_PIP install \
    huggingface_hub[cli] \
    hf_transfer \
    playwright \
    ipython \
    requests \
    pandas

# --- B. 安装 Playwright 浏览器 & 系统依赖 ---
# 这步会下载 Chromium, Firefox 等内核，并安装 Ubuntu 缺少的 .so 库
# 这一步比较耗时，但必须做
RUN $VENV_PYTHON -m playwright install --with-deps

# --- C. 安装 IndexTTS2 (假设是 PyPI 包) ---
# 如果 https://indextts2.org 指向的是一个私有包，需要改成 git clone 安装
RUN $VENV_PIP install indexTTS2 || echo "indexTTS2 not found on PyPI, skipping..."

# --- D. 安装 BettaFish (从 GitHub) ---
WORKDIR /workspace
# Clone 仓库
RUN git clone https://github.com/666ghj/BettaFish.git /workspace/BettaFish
# 安装 BettaFish 的依赖 (假设它有 requirements.txt)
# 如果它没有 requirements.txt，你可能需要手动查看它的文档安装
RUN if [ -f "/workspace/BettaFish/requirements.txt" ]; then \
        $VENV_PIP install -r /workspace/BettaFish/requirements.txt; \
    fi
# 如果需要安装它自己
# RUN cd /workspace/BettaFish && $VENV_PIP install .

# ==============================================================================
# 6. 设置环境变量 & 启动
# ==============================================================================
# 开启 HuggingFace 极速下载模式
ENV HF_HUB_ENABLE_HF_TRANSFER=1

# 把虚拟环境的 bin 加入 PATH，这样 SSH 进来直接输入 python 就是虚拟环境的 python
ENV PATH="$VENV_PATH/bin:$PATH"

# 4. 复制依赖并安装
COPY requirements.txt /tmp/requirements.txt
RUN uv pip install --system -r /tmp/requirements.txt

WORKDIR /workspace

# ==============================================================================
# 8. 安装 Cloudflare Tunnel (cloudflared)
# ==============================================================================
RUN mkdir -p --mode=0755 /usr/share/keyrings && \
    curl -fsSL https://pkg.cloudflare.com/cloudflare-main.gpg | tee /usr/share/keyrings/cloudflare-main.gpg >/dev/null && \
    echo 'deb [signed-by=/usr/share/keyrings/cloudflare-main.gpg] https://pkg.cloudflare.com/cloudflared jammy main' | tee /etc/apt/sources.list.d/cloudflared.list && \
    apt-get update && apt-get install -y cloudflared

# ==============================================================================
# 9. 准备启动脚本 (Entrypoint)
# ==============================================================================
# 我们创建一个启动脚本，用来同时启动 cloudflared 和 sshd
COPY start_services.sh /root/start_services.sh
RUN chmod +x /root/start_services.sh


# 5. 【重要】启动命令
# 告诉容器启动时开启 SSH 服务，并且保持运行
CMD ["/usr/sbin/sshd", "-D"]
