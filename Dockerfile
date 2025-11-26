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
    && rm -rf /var/lib/apt/lists/*

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

# 3. 安装 uv
RUN pip install uv

# 4. 复制依赖并安装
COPY requirements.txt /tmp/requirements.txt
RUN uv pip install --system -r /tmp/requirements.txt

WORKDIR /workspace

# 5. 【重要】启动命令
# 告诉容器启动时开启 SSH 服务，并且保持运行
CMD ["/usr/sbin/sshd", "-D"]
