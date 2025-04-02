#!/bin/bash

echo "Choose how to run the application:"
echo "1) Run with Go directly"
echo "2) Run with podman-compose (recommended)"
read -p "Enter your choice (1 or 2): " choice

case $choice in
    1)
        echo "Running with Go directly..."
        go run main.go
        ;;
    2)
        echo "Running with podman-compose..."
        podman-compose up --build
        ;;
    *)
        echo "Invalid choice. Please enter 1 or 2."
        exit 1
        ;;
esac 