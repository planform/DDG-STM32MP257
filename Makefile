.PHONY: tfa optee uboot fip metadata

tfa:
	+bash scripts/build-tfa.sh

optee:
	+bash scripts/build-optee.sh

uboot:
	+bash scripts/build-uboot.sh

fip:
	+bash scripts/pack-fip.sh

metadata:
	+bash scripts/gen-metadata.sh
