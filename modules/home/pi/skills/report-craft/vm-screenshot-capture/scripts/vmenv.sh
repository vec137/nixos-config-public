#!/usr/bin/env bash
# Общие переменные для работы с несколькими ВМ одновременно.
# Задаются через окружение:
#   CYVM   — имя ВМ в VirtualBox (по умолчанию исходная "CyberOps Workstation")
#   CYPORT — хостовый порт, проброшенный на 22 гостя (по умолчанию 2222)
# Пример: CYVM=CyOps-L7 CYPORT=2227 ./cy.sh 'hostname'
: "${CYVM:=CyberOps Workstation}"
: "${CYPORT:=2222}"
export CYVM CYPORT
