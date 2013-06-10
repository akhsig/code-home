#!/bin/bash

for f in `cat abstract.csv`
do
	wget ${f}
done
