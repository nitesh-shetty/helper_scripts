Running ./nvme_vf_helper.sh will show the usage.

Expected pattern of usage is as below:

Step1:
Lets say the primary controller is /dev/nvme4,
to create single VF for this, run

$ ./nvme_vf_helper.sh cvf -d /dev/nvme4

You can verify the VF using
$lspci | grep -i Vol
or
$sudo nvme list -v

Step2:
Lets VF was created with BDF 0000:ca:04.0
To attach this BDF with libnvm/BAM driver,
assuming BAM driver is already loaded.

$./nvme_vf_helper.sh adb -b 0000:ca:04.0 -k libnvm_helper

You can verify the driver node creation using

$ls /dev/libnvm0

Step 3:
Now assuming we are done with GPU test and want to reattach the driver back to nvme
$./nvme_vf_helper.sh adb -b 0000:ca:04.0 -k nvme

Step 4:
You longer need the secondary controller created in step 1,
assuming /dev/nvme4 is your primary controller
$./nvme_vf_helper.sh dvf -d /dev/nvme4


Good luck !!
