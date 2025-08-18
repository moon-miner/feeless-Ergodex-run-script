#!/usr/bin/env bash

# ===========================================
# Ergo DEX Setup & Run Script
# Fully self-contained and idempotent
# Works on clean Linux installations
# Intelligent step checking - only does what's needed
# Updated for ergodex branch and Node.js v20
# ===========================================

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_skip() {
    echo -e "${BLUE}[SKIP]${NC} $1"
}

log_debug() {
    if [ "${DEBUG:-}" = "1" ]; then
        echo -e "${BLUE}[DEBUG]${NC} $1"
    fi
}

# --- Detect Linux distribution ---
detect_distro() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        echo "$ID"
    else
        echo "unknown"
    fi
}

DISTRO=$(detect_distro)
log_info "Detected distribution: $DISTRO"

# --- Check if basic packages are installed ---
check_basic_packages() {
    local missing_packages=()

    # Check for essential tools
    command -v curl >/dev/null 2>&1 || missing_packages+=("curl")
    command -v wget >/dev/null 2>&1 || missing_packages+=("wget")
    command -v git >/dev/null 2>&1 || missing_packages+=("git")
    command -v gcc >/dev/null 2>&1 || missing_packages+=("build-tools")
    command -v make >/dev/null 2>&1 || missing_packages+=("make")
    command -v python3 >/dev/null 2>&1 || missing_packages+=("python3")

    if [ ${#missing_packages[@]} -eq 0 ]; then
        log_skip "Basic packages already installed"
        return 1  # Skip installation
    else
        log_info "Missing packages: ${missing_packages[*]}"
        return 0  # Need installation
    fi
}

# --- Clean any problematic NodeSource repositories ---
clean_node_repos() {
    local cleaned=false

    if [ -f /etc/apt/sources.list.d/nodesource.list ] || [ -f /etc/apt/sources.list.d/nodejs.list ]; then
        log_info "Cleaning existing NodeSource repositories..."

        # Remove NodeSource repository files
        sudo rm -f /etc/apt/sources.list.d/nodesource.list 2>/dev/null || true
        sudo rm -f /etc/apt/sources.list.d/nodejs.list 2>/dev/null || true

        # Remove NodeSource GPG keys
        sudo apt-key del 1655A0AB68576280 2>/dev/null || true
        sudo apt-key del 68576280 2>/dev/null || true

        # Remove from trusted.gpg.d if present
        sudo rm -f /etc/apt/trusted.gpg.d/nodesource.gpg 2>/dev/null || true

        cleaned=true
        log_info "NodeSource cleanup completed"
    else
        log_skip "No NodeSource repositories to clean"
    fi

    return $cleaned
}

# --- Install required packages depending on distro ---
install_packages() {
    if ! check_basic_packages; then
        return 0
    fi

    case "$DISTRO" in
        ubuntu|debian)
            clean_node_repos
            log_info "Updating package lists..."
            sudo apt update
            log_info "Installing base packages..."
            sudo apt install -y curl wget git build-essential python3 python3-pip
            ;;
        fedora)
            log_info "Installing base packages..."
            sudo dnf install -y curl wget git @development-tools python3 python3-pip
            ;;
        arch)
            log_info "Installing base packages..."
            sudo pacman -Sy --noconfirm curl wget git base-devel python python-pip
            ;;
        opensuse*|sles)
            log_info "Installing base packages..."
            sudo zypper install -y curl wget git gcc gcc-c++ make python3 python3-pip
            ;;
        centos|rhel)
            log_info "Installing base packages..."
            sudo yum groupinstall -y "Development Tools"
            sudo yum install -y curl wget git python3 python3-pip
            ;;
        *)
            log_warn "Unsupported distro: $DISTRO"
            log_warn "Please ensure curl, wget, git, and build tools are installed manually."
            ;;
    esac
}

# --- Check if NVM is installed and working ---
check_nvm_installed() {
    if [ -s "$HOME/.nvm/nvm.sh" ]; then
        export NVM_DIR="$HOME/.nvm"
        [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
        [ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"

        if command -v nvm >/dev/null 2>&1; then
            local nvm_version=$(nvm --version 2>/dev/null || echo "unknown")
            log_skip "NVM already installed (version: $nvm_version)"
            return 0  # Already installed
        fi
    fi
    return 1  # Not installed
}

# --- Install NVM (Node Version Manager) ---
install_nvm() {
    if check_nvm_installed; then
        return 0
    fi

    log_info "Installing NVM (Node Version Manager)..."

    # Download and install NVM
    curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.4/install.sh | bash

    # Load NVM
    export NVM_DIR="$HOME/.nvm"
    [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
    [ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"

    log_info "NVM installed successfully"
}

# --- Check if Node.js v20 is installed and set as default ---
check_node_v20() {
    # Ensure NVM is loaded
    export NVM_DIR="$HOME/.nvm"
    [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"

    if command -v node >/dev/null 2>&1; then
        local current_version=$(node -v 2>/dev/null || echo "none")
        local default_version=$(nvm alias default 2>/dev/null || echo "none")

        # Check if Node v20 is installed and is the default
        if [[ "$current_version" == v20.* ]] && [[ "$default_version" == v20.* ]]; then
            log_skip "Node.js v20 already installed and set as default ($current_version)"
            return 0  # Already correct
        elif nvm ls 20 >/dev/null 2>&1; then
            log_info "Node.js v20 installed but not active. Setting as default..."
            nvm alias default 20
            nvm use 20
            return 0  # Fixed
        fi
    fi
    return 1  # Need to install
}

# --- Install Node.js v20 using NVM ---
install_node_v20() {
    if check_node_v20; then
        return 0
    fi

    log_info "Installing Node.js v20..."

    # Ensure NVM is loaded
    export NVM_DIR="$HOME/.nvm"
    [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"

    # Install Node.js v20
    nvm install 20
    nvm alias default 20
    nvm use 20

    # Verify installation
    NODE_VERSION=$(node -v)
    NPM_VERSION=$(npm -v)

    log_info "Node.js version: $NODE_VERSION"
    log_info "NPM version: $NPM_VERSION"

    # Ensure we're using the right version
    if [[ "$NODE_VERSION" != v20.* ]]; then
        log_error "Failed to install Node.js v20. Current version: $NODE_VERSION"
        exit 1
    fi
}

# --- Find vite.config.ts file location ---
find_vite_config_file() {
    log_debug "Searching for vite.config.ts file..."

    if [ -f "interface/vite.config.ts" ]; then
        echo "interface/vite.config.ts"
        return 0
    fi

    return 1  # Not found
}

# --- Check if vite.config.ts is already modified ---
check_vite_config_modified() {
    log_debug "Checking if vite.config.ts is modified..."

    local target_file
    target_file=$(find_vite_config_file)
    local find_result=$?

    if [ $find_result -ne 0 ] || [ -z "$target_file" ]; then
        log_warn "vite.config.ts file not found in repository"
        return 2  # File not found
    fi

    log_debug "Found vite.config.ts at: $target_file"

    # Check if already modified - look for our modification comment
    if grep -q "// ESLint disabled to suppress warnings" "$target_file"; then
        log_skip "vite.config.ts already modified (ESLint warnings disabled)"
        return 0  # Already modified
    fi

    log_debug "vite.config.ts needs modification"
    return 1  # Not modified
}

# --- Modify vite.config.ts to disable ESLint warnings ---
update_vite_config() {
    log_info "Checking Vite configuration..."

    local modify_status

    # Disable exit-on-error temporarily to capture return codes properly
    set +e
    check_vite_config_modified
    modify_status=$?
    set -e

    case $modify_status in
        0)
            # Already modified
            log_info "Vite configuration already updated (ESLint disabled)"
            return 0
            ;;
        2)
            # File not found
            log_warn "vite.config.ts file not found. Repository structure may have changed."
            log_warn "This is not critical - ESLint warnings may still appear."
            return 0  # Continue anyway
            ;;
        1)
            # Need to modify
            ;;
    esac

    local target_file
    target_file=$(find_vite_config_file)

    if [ -z "$target_file" ]; then
        log_error "Could not locate vite.config.ts file"
        return 1
    fi

    log_info "Updating vite.config.ts to disable ESLint warnings..."
    log_info "Target file: $target_file"

    # Create backup
    cp "$target_file" "$target_file.backup"
    log_info "Created backup: $target_file.backup"

    # Write the modified content (removing ESLint from checker plugin)
    cat > "$target_file" << 'EOF'
import { lingui } from '@lingui/vite-plugin';
import { VitePWA } from 'vite-plugin-pwa'
import pluginRewriteAll from 'vite-plugin-rewrite-all'
import inject from '@rollup/plugin-inject';
import react from '@vitejs/plugin-react';
import * as fs from 'fs';
import path from 'path';
import { defineConfig } from 'vite';
import checker from 'vite-plugin-checker';
import svgr from 'vite-plugin-svgr';
import topLevelAwait from 'vite-plugin-top-level-await';
import wasm from 'vite-plugin-wasm';

// https://vitejs.dev/config/
export default defineConfig({
  // This changes the output dir from dist to build
  // comment this out if that isn't relevant for your project
  build: {
    outDir: 'build',
    rollupOptions: {
      plugins: [inject({ Buffer: ['buffer', 'Buffer'], process: 'process' })],
    },
  },
  plugins: [
    pluginRewriteAll(),
    react({
      babel: {
        plugins: ['macros'],
      },
    }),
    // ESLint disabled to suppress warnings
    checker({
      typescript: true,
      // eslint: {
      //   lintCommand: 'eslint --ext .js,.ts,.tsx src',
      // },
    }),
    lingui(),
    wasm(),
    topLevelAwait(),
    svgr({ svgrOptions: { icon: true } }),
    reactVirtualized(),
    VitePWA({
      registerType: 'autoUpdate',
      workbox: {
        globPatterns: ['**/*.{js,css,html,ico,png,svg}']
      }
    })
  ],
  resolve: {
    alias: [
      {
        find: /^~(.*)$/,
        replacement: '$1',
      },
    ],
  },
  css: {
    preprocessorOptions: {
      less: {
        javascriptEnabled: true,
      },
    },
  },
  server: {
    port: 3000,
  },
});

const WRONG_CODE = `import { bpfrpt_proptype_WindowScroller } from "../WindowScroller.js";`;
export function reactVirtualized() {
  return {
    name: 'my:react-virtualized',
    configResolved() {
      const file = require
        .resolve('react-virtualized')
        .replace(
          path.join('dist', 'commonjs', 'index.js'),
          path.join('dist', 'es', 'WindowScroller', 'utils', 'onScroll.js'),
        );
      const code = fs.readFileSync(file, 'utf-8');
      const modified = code.replace(WRONG_CODE, '');
      fs.writeFileSync(file, modified);
    },
  };
}
EOF

    if [ $? -eq 0 ]; then
        log_info "vite.config.ts updated successfully (ESLint warnings disabled)"
    else
        log_error "Failed to update vite.config.ts"
        # Restore backup
        if [ -f "$target_file.backup" ]; then
            cp "$target_file.backup" "$target_file"
            log_info "Restored original file from backup"
        fi
        return 1
    fi
}

# --- Check if Yarn is installed ---
check_yarn_installed() {
    # Ensure NVM and Node are loaded
    export NVM_DIR="$HOME/.nvm"
    [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
    nvm use 20 >/dev/null 2>&1

    if command -v yarn >/dev/null 2>&1; then
        local yarn_version=$(yarn -v 2>/dev/null || echo "unknown")
        log_skip "Yarn already installed (version: $yarn_version)"
        return 0  # Already installed
    fi
    return 1  # Not installed
}

# --- Install Yarn package manager ---
install_yarn() {
    if check_yarn_installed; then
        return 0
    fi

    # Ensure NVM and Node are loaded
    export NVM_DIR="$HOME/.nvm"
    [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
    nvm use 20

    log_info "Installing Yarn package manager..."
    npm install -g yarn

    local yarn_version=$(yarn -v)
    log_info "Yarn installed: $yarn_version"
}

# --- Check if repository exists and is up to date ---
check_repo_status() {
    log_info "Checking repository status..."

    if [ ! -d "interface" ]; then
        log_info "Repository not found, will need to clone"
        return 1  # Need to clone
    fi

    cd interface

    # Check if it's a git repository
    if [ ! -d ".git" ]; then
        cd ..
        log_warn "interface directory exists but is not a git repository"
        return 1  # Need to re-clone
    fi

    # Check remote URL
    local remote_url=$(git remote get-url origin 2>/dev/null || echo "")
    if [[ "$remote_url" != *"spectrum-finance/interface"* ]]; then
        cd ..
        log_warn "interface directory has wrong remote URL: $remote_url"
        return 1  # Need to re-clone
    fi

    # Check if we can pull (repository is accessible and has updates)
    log_info "Checking for repository updates..."

    # Set git to not prompt for credentials and use timeout
    export GIT_TERMINAL_PROMPT=0
    export GIT_ASKPASS=/bin/echo

    # Try fetch with timeout and capture output
    log_info "Attempting to fetch from remote..."
    if timeout 10s git fetch origin --quiet 2>/dev/null; then
        log_info "Fetch successful, comparing commits..."
        local local_commit=$(git rev-parse HEAD 2>/dev/null || echo "")
        local remote_ergodex=$(git rev-parse origin/ergodex 2>/dev/null || echo "")

        # Check if we're on the right branch
        local current_branch=$(git branch --show-current 2>/dev/null || echo "")
        if [ "$current_branch" != "ergodex" ]; then
            log_info "Not on ergodex branch (current: $current_branch), will need to switch"
            cd ..
            return 2  # Need to update
        fi

        # Use ergodex branch
        local remote_commit=""
        if [ -n "$remote_ergodex" ]; then
            remote_commit="$remote_ergodex"
            log_info "Using ergodex branch"
        else
            log_warn "Could not find ergodex branch"
            cd ..
            return 2  # Need to update/checkout ergodex
        fi

        log_info "Local commit: ${local_commit:0:8}"
        log_info "Remote commit: ${remote_commit:0:8}"

        cd ..

        if [ -n "$local_commit" ] && [ -n "$remote_commit" ] && [ "$local_commit" = "$remote_commit" ]; then
            log_skip "Repository already up to date"
            return 0  # Up to date
        else
            log_info "Repository updates available"
            return 2  # Need to update
        fi
    else
        cd ..
        log_warn "Cannot fetch from remote repository (timeout or network issue)"
        log_info "Will continue with current repository state"
        return 0  # Continue with what we have
    fi
}

# --- Clone or update the ErgoDEX repository ---
setup_repo() {
    log_info "Checking repository setup..."

    local repo_status

    # Disable exit-on-error temporarily to capture return codes properly
    set +e
    check_repo_status
    repo_status=$?
    set -e

    case $repo_status in
        0)
            # Repository is up to date
            log_info "Repository setup complete"
            return 0
            ;;
        1)
            # Need to clone
            if [ -d "interface" ]; then
                log_info "Removing existing interface directory..."
                rm -rf interface
            fi
            log_info "Cloning ErgoDEX repository..."
            git clone https://github.com/spectrum-finance/interface
            cd interface
            log_info "Checking out ergodex branch..."
            git checkout ergodex
            cd ..
            log_info "Repository cloned successfully (ergodex branch)"
            ;;
        2)
            # Need to update
            log_info "Updating ErgoDEX repository..."
            cd interface

            # Set git to not prompt and use timeout
            export GIT_TERMINAL_PROMPT=0
            export GIT_ASKPASS=/bin/echo

            # Make sure we're on ergodex branch
            log_info "Switching to ergodex branch..."
            git checkout ergodex 2>/dev/null || {
                log_warn "Could not checkout ergodex branch, trying to create it"
                git checkout -b ergodex origin/ergodex 2>/dev/null || log_warn "Could not create ergodex branch"
            }

            # Try to pull from ergodex branch
            log_info "Pulling from origin/ergodex..."
            if timeout 15s git pull origin ergodex --quiet 2>/dev/null; then
                log_info "Repository updated successfully"
            else
                log_warn "Failed to pull updates (timeout or conflicts)"
                log_info "Attempting to reset and pull..."
                git reset --hard HEAD >/dev/null 2>&1
                if timeout 15s git pull origin ergodex --quiet 2>/dev/null; then
                    log_info "Repository updated successfully after reset"
                else
                    log_warn "Could not update repository, continuing with current version"
                fi
            fi
            cd ..
            ;;
    esac

    log_info "Repository setup complete"
}

# --- Find uiFee.ts file location ---
find_ui_fee_file() {
    log_debug "Searching for uiFee.ts file..."

    # Common possible locations
    local possible_locations=(
        "interface/src/network/ergo/api/uiFee/uiFee.ts"
        "interface/src/network/ergo/api/uiFee.ts"
        "interface/src/api/uiFee/uiFee.ts"
        "interface/src/uiFee/uiFee.ts"
    )

    # Check predefined locations first
    for location in "${possible_locations[@]}"; do
        if [ -f "$location" ]; then
            echo "$location"
            return 0
        fi
    done

    # Search in the entire interface directory
    if [ -d "interface" ]; then
        local found_file=$(find interface/ -name "uiFee.ts" -type f 2>/dev/null | head -1)
        if [ -n "$found_file" ]; then
            echo "$found_file"
            return 0
        fi
    fi

    return 1  # Not found
}

# --- Check if uiFee.ts is already modified ---
check_ui_fee_modified() {
    log_debug "Checking if uiFee.ts is modified..."

    local target_file
    target_file=$(find_ui_fee_file)
    local find_result=$?

    if [ $find_result -ne 0 ] || [ -z "$target_file" ]; then
        log_warn "uiFee.ts file not found in repository"
        log_info "Searching for uiFee files..."
        find interface/ -name "*uiFee*" -type f 2>/dev/null | while read -r file; do
            log_info "Found related file: $file"
        done
        return 2  # File not found
    fi

    log_debug "Found uiFee.ts at: $target_file"

    # Check if file contains our modification marker comments
    if grep -q "// Modified: UI fees disabled" "$target_file" && \
       grep -q "// Modified: Always return 0% fee instead of calculating percentage" "$target_file" && \
       grep -q "// Modified: UI fees disabled by setting all values to 0" "$target_file"; then
        log_skip "uiFee.ts already modified (UI fees disabled with custom implementation)"
        return 0  # Already modified
    fi

    # Additional check: verify the key modification is present
    if grep -q "const uiFeeInErg = inputInErg.percent(0)" "$target_file" && \
       grep -q "uiFeePercent: 0" "$target_file"; then
        log_skip "uiFee.ts already modified (UI fees disabled - found key modifications)"
        return 0  # Already modified
    fi

    log_debug "uiFee.ts needs modification (not found modification markers)"
    return 1  # Not modified
}

# --- Replace uiFee.ts with modified version (removes fees) ---
update_ui_fee() {
    log_info "Checking UI fee configuration..."

    local modify_status

    # Disable exit-on-error temporarily to capture return codes properly
    set +e
    check_ui_fee_modified
    modify_status=$?
    set -e

    case $modify_status in
        0)
            # Already modified
            log_info "UI fee configuration already updated"
            return 0
            ;;
        2)
            # File not found
            log_warn "uiFee.ts file not found. Repository structure may have changed."
            log_warn "This is not critical - the application may work without this modification."
            log_warn "You can manually disable fees in the UI if needed."
            return 0  # Continue anyway
            ;;
        1)
            # Need to modify
            ;;
    esac

    local target_file
    target_file=$(find_ui_fee_file)

    if [ -z "$target_file" ]; then
        log_error "Could not locate uiFee.ts file"
        return 1
    fi

    log_info "Updating uiFee.ts to disable UI fees..."
    log_info "Target file: $target_file"

    # Create backup with timestamp
    local backup_file="${target_file}.backup.$(date +%Y%m%d_%H%M%S)"
    cp "$target_file" "$backup_file"
    log_info "Created backup: $backup_file"

    # Write the modified content
    cat > "$target_file" << 'EOF'
// Modified: UI fees disabled
import {
  BehaviorSubject,
  combineLatest,
  debounceTime,
  distinctUntilChanged,
  map,
  Observable,
  of,
  publishReplay,
  refCount,
} from 'rxjs';

import { usdAsset } from '../../../../common/constants/usdAsset';
import { Currency } from '../../../../common/models/Currency';
import { Ratio } from '../../../../common/models/Ratio';
import { convertToConvenientNetworkAsset } from '../ergoUsdRatio/ergoUsdRatio';
import { networkAsset } from '../networkAsset/networkAsset';

export interface UiFeeParams {
  readonly address: string;
  readonly minUiFee: number;
  readonly uiFeePercent: number;
  readonly uiFeeThreshold: number;
}

// Modified: UI fees disabled by setting all values to 0
export const uiFeeParams$ = new BehaviorSubject<UiFeeParams>({
  address: '',
  minUiFee: 0,
  uiFeePercent: 0,
  uiFeeThreshold: 30,
});

const _calculateUiFee = (
  usdErgRate: Ratio,
  inputInErg: Currency,
  params: UiFeeParams,
): Currency => {
  const minUiFeeInErg = usdErgRate.toBaseCurrency(
    new Currency(params.minUiFee.toString(), usdAsset),
  );
  const feeThresholdInErg = usdErgRate.toBaseCurrency(
    new Currency(params.uiFeeThreshold.toString(), usdAsset),
  );
  if (!inputInErg.isAssetEquals(networkAsset)) {
    return minUiFeeInErg;
  }
  if (inputInErg.lte(feeThresholdInErg)) {
    return minUiFeeInErg;
  }
  // Modified: Always return 0% fee instead of calculating percentage
  const uiFeeInErg = inputInErg.percent(0);

  return uiFeeInErg.gte(minUiFeeInErg) ? uiFeeInErg : minUiFeeInErg;
};

export const minUiFee$: Observable<Currency> = combineLatest([
  convertToConvenientNetworkAsset.rate(networkAsset),
  uiFeeParams$,
]).pipe(
  map(([usdErgRate, params]) =>
    usdErgRate.toBaseCurrency(
      new Currency(params.minUiFee.toString(), usdAsset),
    ),
  ),
  publishReplay(1),
  refCount(),
);

export const calculateUiFeeSync = (
  input: Currency = new Currency(0n, networkAsset),
): Currency => {
  const usdErgRate = convertToConvenientNetworkAsset.rateSnapshot(networkAsset);
  const inputInErg =
    input.asset.id === networkAsset.id
      ? input
      : convertToConvenientNetworkAsset.snapshot(input, networkAsset);
  const uiFeeParams = uiFeeParams$.getValue();
  return _calculateUiFee(usdErgRate, inputInErg, uiFeeParams);
};

export const calculateUiFee = (
  input: Currency = new Currency(0n, networkAsset),
): Observable<Currency> =>
  combineLatest([
    convertToConvenientNetworkAsset.rate(networkAsset),
    input.asset.id === networkAsset.id
      ? of(input)
      : convertToConvenientNetworkAsset(input, networkAsset),
    uiFeeParams$,
  ]).pipe(
    debounceTime(200),
    map(([usdErgRate, inputInErg, params]: [Ratio, Currency, UiFeeParams]) =>
      _calculateUiFee(usdErgRate, inputInErg, params),
    ),
    distinctUntilChanged(
      (prev, current) => prev?.toAmount() === current?.toAmount(),
    ),
  );
EOF

    if [ $? -eq 0 ]; then
        log_info "uiFee.ts updated successfully (UI fees disabled)"

        # Verify the modification was applied correctly
        if grep -q "// Modified: UI fees disabled" "$target_file" && \
           grep -q "uiFeePercent: 0" "$target_file"; then
            log_info "Modification verification: SUCCESS"
        else
            log_warn "Modification verification: File written but markers not found"
        fi
    else
        log_error "Failed to update uiFee.ts"
        # Restore backup
        if [ -f "$backup_file" ]; then
            cp "$backup_file" "$target_file"
            log_info "Restored original file from backup: $backup_file"
        fi
        return 1
    fi
}

# --- Check if dependencies are installed ---
check_dependencies_installed() {
    if [ ! -d "interface/node_modules" ]; then
        return 1  # Need to install
    fi

    # Check if package.json has changed since last install
    local package_json="interface/package.json"
    local lock_file="interface/yarn.lock"

    if [ ! -f "$lock_file" ]; then
        return 1  # No lock file, need to install
    fi

    # Check if package.json is newer than node_modules
    if [ "$package_json" -nt "interface/node_modules" ]; then
        log_info "package.json has been updated, need to reinstall dependencies"
        return 1  # Need to reinstall
    fi

    log_skip "Dependencies already installed and up to date"
    return 0  # Already installed
}

# --- Install dependencies and run the application ---
build_and_run() {
    log_info "Entering interface directory..."

    if [ ! -d "interface" ]; then
        log_error "Interface directory not found!"
        exit 1
    fi

    cd interface

    # Ensure we're using Node v20
    log_info "Loading Node.js environment..."
    export NVM_DIR="$HOME/.nvm"
    [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
    nvm use 20

    log_info "Current Node.js version: $(node -v)"
    log_info "Current NPM version: $(npm -v)"
    log_info "Current Yarn version: $(yarn -v)"

    # Check and install dependencies if needed
    if ! check_dependencies_installed; then
        log_info "Installing project dependencies... (this may take a few minutes)"
        log_info "Running: yarn"
        if yarn --network-timeout 100000; then
            log_info "Dependencies installed successfully"
        else
            log_error "Failed to install dependencies"
            cd ..
            exit 1
        fi
    fi

    log_info "Starting ErgoDEX development server..."
    log_info "The application will be available at: http://localhost:3000"
    log_info "Press Ctrl+C to stop the server"
    log_info ""
    log_info "Starting in 3 seconds..."
    sleep 1
    log_info "Starting in 2 seconds..."
    sleep 1
    log_info "Starting in 1 second..."
    sleep 1
    log_info "Starting now!"

    # Start the development server (ESLint disabled via vite.config.ts modification)
    yarn start
}

# --- Display summary of what will be done ---
show_summary() {
    log_info "=== ErgoDEX Setup Summary ==="

    echo "Checking current status..."

    # Check each component with safe repository check
    local needs_packages=false
    local needs_nvm=false
    local needs_node=false
    local needs_yarn=false
    local needs_repo=false
    local needs_ui_fee=false
    local needs_deps=false

    check_basic_packages || needs_packages=true
    check_nvm_installed || needs_nvm=true
    check_node_v20 || needs_node=true
    check_yarn_installed || needs_yarn=true

    # Simple repository check for summary
    if [ ! -d "interface" ] || [ ! -d "interface/.git" ]; then
        needs_repo=true
    else
        log_info "Repository exists, will check for updates during setup"
        needs_repo=true  # Always check during actual setup
    fi

    check_ui_fee_modified || needs_ui_fee=true
    check_dependencies_installed || needs_deps=true

    echo ""
    echo "Actions planned:"
    [ "$needs_packages" = true ] && echo "  ✓ Install basic packages (curl, git, build tools)" || echo "  ✗ Basic packages (already installed)"
    [ "$needs_nvm" = true ] && echo "  ✓ Install NVM" || echo "  ✗ NVM (already installed)"
    [ "$needs_node" = true ] && echo "  ✓ Install Node.js v20" || echo "  ✗ Node.js v20 (already installed)"
    [ "$needs_yarn" = true ] && echo "  ✓ Install Yarn" || echo "  ✗ Yarn (already installed)"
    [ "$needs_repo" = true ] && echo "  ✓ Check/update ErgoDEX repository (ergodex branch)" || echo "  ✗ Repository (already up to date)"
    [ "$needs_ui_fee" = true ] && echo "  ✓ Modify UI fee configuration" || echo "  ✗ UI fee (already modified)"
    [ "$needs_deps" = true ] && echo "  ✓ Install project dependencies" || echo "  ✗ Dependencies (already installed)"
    echo "  ✓ Start development server"
    echo ""

    # Ask for confirmation if not in CI
    if [ -t 1 ] && [ -z "$CI" ]; then
        echo -n "Continue? [Y/n] "
        read -r response
        case "$response" in
            [nN][oO]|[nN])
                log_info "Setup cancelled by user"
                exit 0
                ;;
        esac
    fi
}

# --- Main execution flow ---
main() {
    log_info "=== ErgoDEX Setup & Run Script ==="
    log_info "Updated for ergodex branch and Node.js v20"

    # Show what will be done
    show_summary

    echo ""
    log_info "Starting setup process..."

    # Execute all steps (each step checks if it's needed)
    log_info "Step 1: Installing packages..."
    install_packages

    log_info "Step 2: Installing NVM..."
    install_nvm

    log_info "Step 3: Installing Node.js v20..."
    install_node_v20

    log_info "Step 4: Installing Yarn..."
    install_yarn

    log_info "Step 5: Setting up repository (ergodex branch)..."
    setup_repo

    log_info "Step 6: Updating UI fee configuration..."
    update_ui_fee

    log_info "Step 7: Updating Vite configuration..."
    update_vite_config

    log_info "Step 8: Building and running application..."
    build_and_run
}

# --- Error handling ---
trap 'log_error "Script interrupted. Cleaning up..."; exit 1' INT TERM

# Check if running as root (not recommended)
if [ "$EUID" -eq 0 ]; then
    log_warn "Running as root is not recommended for development"
    log_warn "Consider running as a regular user"
fi

# Enable debug mode if requested
if [ "${1:-}" = "--debug" ] || [ "${DEBUG:-}" = "1" ]; then
    export DEBUG=1
    log_info "Debug mode enabled"
fi

# Run main function
main
