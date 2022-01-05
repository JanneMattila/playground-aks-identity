# Playground AKS Identity

This repository contains identity related examples.

## Azure AD related examples

1. Simple application that shows how you can acquire token inside your pod
2. Azure CLI based automation that uses managed identity for connecting to Azure

## Usage

1. Clone this repository to your own machine
2. Open Workspace
  - Use WSL in Windows
  - Requires Bash
3. Open [setup.sh](setup.sh) to walk through steps to deploy this demo environment
  - Execute different script steps one-by-one (hint: use [shift-enter](https://github.com/JanneMattila/some-questions-and-some-answers/blob/master/q%26a/vs_code.md#automation-tip-shift-enter))

## Deployment related permissions example

Example how you can test minimal required permissions, if
you have separate Platform team and App team and you want to
customize your deployment process.

See [deployment permissions](./deployment-permissions) for more details.
