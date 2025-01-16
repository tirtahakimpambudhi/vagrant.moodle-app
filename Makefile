.PHONY: add down up init ssh

BOX=""
BOX_VER=""
PROVIDE=""
HOST=""

add:
	vagrant box add $(BOX) --provide $(PROVIDE)

up:
	vagrant up

ssh:
	vagrant ssh $(HOST)

init:
	vagrant init $(BOX) --box-version $(BOX_VER)

down:
	vagrant destroy -f



