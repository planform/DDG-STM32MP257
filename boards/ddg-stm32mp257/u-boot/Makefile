dtb-$(CONFIG_STM32MP25X) += stm32mp257d-ddg.dtb

targets += $(dtb-y)

DTC_FLAGS += -a 0x8

PHONY += dtbs
dtbs: $(addprefix $(obj)/, $(dtb-y))
	@:

clean-files := *.dtb *.dtbo *_HS
