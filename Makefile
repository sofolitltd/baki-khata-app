API_DIR  := ../baki_khata_api
EMULATOR := emulator-5554
# Mac-এর LAN IP (আসল ফোন একই Wi-Fi তে থাকতে হবে)
LAN_IP   := $(shell ipconfig getifaddr en0)
API_PORT := 8080

.PHONY: help run run-e run-d devices

help:
	@echo "make run      - Go সার্ভার চালু (go run .)"
	@echo "make run-e    - অ্যান্ড্রয়েড এমুলেটরে অ্যাপ চালু"
	@echo "make run-d    - আসল ফোনে অ্যাপ চালু (ঐচ্ছিক: DEVICE=<id>)"
	@echo "make devices  - ডিভাইসের তালিকা"

run:
	$(MAKE) -C $(API_DIR) run PORT=$(API_PORT)

run-e:
	flutter run -d $(EMULATOR)

# আসল ফোনে localhost কাজ করে না, তাই Mac-এর LAN IP দেওয়া হচ্ছে
run-d:
	flutter run $(if $(DEVICE),-d $(DEVICE),) --dart-define=API_URL=http://$(LAN_IP):$(API_PORT)

devices:
	flutter devices
