#!/bin/bash

# Check if Rust is installed
if ! command -v rustc &> /dev/null; then
    echo "Rust is not installed. Installing Rust..."
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh
    source $HOME/.cargo/env
fi

# Navigate to tenant-service directory
cd tenant-service

# Run the service
cargo run 