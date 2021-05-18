#!/bin/sh

./configure
sudo -u "$username" make
make install
