#!/bin/bash
# Homebrew 安装脚本 - 使用清华大学镜像源
# 基于 https://mirrors.tuna.tsinghua.edu.cn/help/homebrew/ 的官方指南

set -e  # 遇到错误立即退出

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 打印带颜色的消息
print_info() {
    echo -e "${BLUE}[信息]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[成功]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[警告]${NC} $1"
}

print_error() {
    echo -e "${RED}[错误]${NC} $1"
}

print_step() {
    echo -e "\n${BLUE}==== $1 ====${NC}"
}

# 检测操作系统和架构
detect_system() {
    print_step "检测系统信息"
    
    OS_TYPE=$(uname -s)
    ARCH=$(uname -m)
    
    print_info "操作系统: $OS_TYPE"
    print_info "系统架构: $ARCH"
    
    case "$OS_TYPE" in
        "Darwin")
            SYSTEM="macOS"
            if [[ "$ARCH" == "arm64" ]]; then
                SYSTEM_VARIANT="Apple Silicon"
                HOMEBREW_PREFIX="/opt/homebrew"
            else
                SYSTEM_VARIANT="Intel"
                HOMEBREW_PREFIX="/usr/local"
            fi
            ;;
        "Linux")
            SYSTEM="Linux"
            SYSTEM_VARIANT="Linux"
            HOMEBREW_PREFIX="/home/linuxbrew/.linuxbrew"
            ;;
        *)
            print_error "不支持的操作系统: $OS_TYPE"
            exit 1
            ;;
    esac
    
    print_success "检测到系统: $SYSTEM ($SYSTEM_VARIANT)"
    print_info "Homebrew 将安装到: $HOMEBREW_PREFIX"
}

# 检查必要的依赖
check_dependencies() {
    print_step "检查系统依赖"
    
    local missing_deps=()
    
    # 检查 bash
    if ! command -v bash &> /dev/null; then
        missing_deps+=("bash")
    else
        print_success "bash 已安装: $(bash --version | head -n1)"
    fi
    
    # 检查 git
    if ! command -v git &> /dev/null; then
        missing_deps+=("git")
    else
        print_success "git 已安装: $(git --version)"
    fi
    
    # 检查 curl
    if ! command -v curl &> /dev/null; then
        missing_deps+=("curl")
    else
        print_success "curl 已安装: $(curl --version | head -n1)"
    fi
    
    # macOS 特殊检查
    if [[ "$SYSTEM" == "macOS" ]]; then
        # 检查 Command Line Tools
        if ! xcode-select -p &> /dev/null; then
            print_warning "Command Line Tools for Xcode 未安装"
            print_info "正在安装 Command Line Tools..."
            xcode-select --install
            print_info "请在弹出的对话框中完成 Command Line Tools 的安装，然后重新运行此脚本"
            exit 1
        else
            print_success "Command Line Tools 已安装: $(xcode-select -p)"
        fi
    fi
    
    # Linux 特殊提示
    if [[ "$SYSTEM" == "Linux" ]]; then
        print_info "Linux 系统检测完成"
        if [[ ${#missing_deps[@]} -gt 0 ]]; then
            print_warning "请使用包管理器安装缺失的依赖："
            print_info "Ubuntu/Debian: sudo apt-get install ${missing_deps[*]}"
            print_info "CentOS/RHEL: sudo yum install ${missing_deps[*]}"
            print_info "Fedora: sudo dnf install ${missing_deps[*]}"
        fi
    fi
    
    # 检查是否有缺失的依赖
    if [[ ${#missing_deps[@]} -gt 0 ]]; then
        print_error "缺失以下依赖: ${missing_deps[*]}"
        exit 1
    fi
    
    print_success "所有依赖检查通过"
}

# 检查 Homebrew 是否已安装
check_existing_homebrew() {
    print_step "检查现有 Homebrew 安装"
    
    if command -v brew &> /dev/null; then
        local brew_version=$(brew --version | head -n1)
        local brew_prefix=$(brew --prefix)
        print_warning "检测到已安装的 Homebrew"
        print_info "版本: $brew_version"
        print_info "安装路径: $brew_prefix"
        
        echo
        read -p "是否要继续安装？这可能会覆盖现有配置 (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            print_info "安装已取消"
            exit 0
        fi
    else
        print_success "未检测到现有 Homebrew 安装，可以继续"
    fi
}

# 设置清华镜像源环境变量
setup_mirror_environment() {
    print_step "配置清华镜像源环境变量"
    
    # 设置镜像源环境变量
    export HOMEBREW_BREW_GIT_REMOTE="https://mirrors.tuna.tsinghua.edu.cn/git/homebrew/brew.git"
    export HOMEBREW_CORE_GIT_REMOTE="https://mirrors.tuna.tsinghua.edu.cn/git/homebrew/homebrew-core.git"
    export HOMEBREW_INSTALL_FROM_API=1
    
    print_success "已设置镜像源环境变量:"
    print_info "HOMEBREW_BREW_GIT_REMOTE=$HOMEBREW_BREW_GIT_REMOTE"
    print_info "HOMEBREW_CORE_GIT_REMOTE=$HOMEBREW_CORE_GIT_REMOTE"
    print_info "HOMEBREW_INSTALL_FROM_API=$HOMEBREW_INSTALL_FROM_API"
}

# 安装 Homebrew
install_homebrew() {
    print_step "安装 Homebrew"
    
    print_info "正在从清华镜像源下载安装脚本..."
    
    # 创建临时目录
    local temp_dir=$(mktemp -d)
    cd "$temp_dir"
    
    # 从镜像源克隆安装脚本
    if git clone --depth=1 https://mirrors.tuna.tsinghua.edu.cn/git/homebrew/install.git brew-install; then
        print_success "安装脚本下载完成"
    else
        print_error "下载安装脚本失败"
        print_info "尝试使用官方源..."
        if ! curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh -o install.sh; then
            print_error "无法下载安装脚本"
            exit 1
        fi
        print_success "从官方源下载安装脚本完成"
    fi
    
    print_info "正在执行 Homebrew 安装..."
    
    # 执行安装脚本
    if [[ -f "brew-install/install.sh" ]]; then
        /bin/bash brew-install/install.sh
    elif [[ -f "install.sh" ]]; then
        /bin/bash install.sh
    else
        print_error "找不到安装脚本"
        exit 1
    fi
    
    # 清理临时文件
    cd - > /dev/null
    rm -rf "$temp_dir"
    
    print_success "Homebrew 安装完成"
}

# 配置环境变量
configure_shell_environment() {
    print_step "配置 Shell 环境变量"
    
    local shell_configs=()
    local brew_shellenv_cmd=""
    
    # 根据系统类型确定配置
    case "$SYSTEM" in
        "macOS")
            if [[ "$SYSTEM_VARIANT" == "Apple Silicon" ]]; then
                brew_shellenv_cmd='eval "$(/opt/homebrew/bin/brew shellenv)"'
            else
                # Intel Mac 通常不需要额外配置，但我们还是添加以确保
                brew_shellenv_cmd='eval "$(/usr/local/bin/brew shellenv)"'
            fi
            shell_configs=("$HOME/.bash_profile" "$HOME/.zprofile")
            ;;
        "Linux")
            brew_shellenv_cmd='eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"'
            shell_configs=("$HOME/.bash_profile" "$HOME/.profile" "$HOME/.zprofile")
            ;;
    esac
    
    print_info "配置 Shell 环境变量: $brew_shellenv_cmd"
    
    # 为每个配置文件添加环境变量
    for config_file in "${shell_configs[@]}"; do
        if [[ -f "$config_file" ]] || [[ "$config_file" == "$HOME/.bash_profile" ]] || [[ "$config_file" == "$HOME/.zprofile" ]]; then
            # 检查是否已经存在配置
            if [[ -f "$config_file" ]] && grep -q "brew shellenv" "$config_file"; then
                print_info "$config_file 中已存在 brew 配置，跳过"
            else
                echo "$brew_shellenv_cmd" >> "$config_file"
                print_success "已添加配置到 $config_file"
            fi
        fi
    done
    
    # 立即应用环境变量
    eval "$brew_shellenv_cmd"
    
    print_success "环境变量配置完成"
}

# 验证安装
verify_installation() {
    print_step "验证 Homebrew 安装"
    
    # 重新加载环境变量
    case "$SYSTEM" in
        "macOS")
            if [[ "$SYSTEM_VARIANT" == "Apple Silicon" ]]; then
                eval "$(/opt/homebrew/bin/brew shellenv)"
            else
                eval "$(/usr/local/bin/brew shellenv)"
            fi
            ;;
        "Linux")
            eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"
            ;;
    esac
    
    # 检查 brew 命令
    if command -v brew &> /dev/null; then
        local brew_version=$(brew --version | head -n1)
        local brew_prefix=$(brew --prefix)
        print_success "Homebrew 安装成功！"
        print_info "版本: $brew_version"
        print_info "安装路径: $brew_prefix"
        
        # 运行 brew doctor 检查
        print_info "正在运行系统检查..."
        if brew doctor; then
            print_success "系统检查通过"
        else
            print_warning "系统检查发现一些问题，但 Homebrew 应该仍能正常工作"
        fi
        
    else
        print_error "Homebrew 安装失败，无法找到 brew 命令"
        print_info "请尝试重新启动终端或手动执行以下命令："
        case "$SYSTEM" in
            "macOS")
                if [[ "$SYSTEM_VARIANT" == "Apple Silicon" ]]; then
                    print_info 'eval "$(/opt/homebrew/bin/brew shellenv)"'
                else
                    print_info 'eval "$(/usr/local/bin/brew shellenv)"'
                fi
                ;;
            "Linux")
                print_info 'eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"'
                ;;
        esac
        exit 1
    fi
}

# 显示后续步骤
show_next_steps() {
    print_step "安装完成"
    
    print_success "🎉 Homebrew 安装成功！"
    echo
    print_info "后续步骤："
    print_info "1. 重新启动终端或执行 'source ~/.bash_profile' (或 ~/.zprofile)"
    print_info "2. 运行 'brew --version' 验证安装"
    print_info "3. 运行 'brew install <package>' 安装软件包"
    echo
    print_info "常用命令："
    print_info "• brew search <关键词>     - 搜索软件包"
    print_info "• brew install <包名>      - 安装软件包"
    print_info "• brew uninstall <包名>    - 卸载软件包"
    print_info "• brew update             - 更新 Homebrew"
    print_info "• brew upgrade            - 升级已安装的软件包"
    print_info "• brew list               - 列出已安装的软件包"
    print_info "• brew doctor             - 检查系统问题"
    echo
    print_info "镜像源信息："
    print_info "本安装使用了清华大学镜像源，享受更快的下载速度"
    print_info "镜像源地址: https://mirrors.tuna.tsinghua.edu.cn/help/homebrew/"
}

# 主函数
main() {
    echo -e "${GREEN}"
    echo "=================================================="
    echo "    Homebrew 安装脚本 (清华镜像源版本)"
    echo "=================================================="
    echo -e "${NC}"
    echo
    print_info "本脚本将使用清华大学镜像源安装 Homebrew"
    print_info "基于官方指南: https://mirrors.tuna.tsinghua.edu.cn/help/homebrew/"
    echo
    
    # 执行安装步骤
    detect_system
    check_dependencies
    check_existing_homebrew
    setup_mirror_environment
    install_homebrew
    configure_shell_environment
    verify_installation
    show_next_steps
    
    print_success "安装流程全部完成！"
}

# 错误处理
trap 'print_error "安装过程中发生错误，请检查上面的错误信息"; exit 1' ERR

# 执行主函数
main "$@"