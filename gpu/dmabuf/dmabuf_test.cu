#include <cuda.h>
// #include <cuda_runtime_api.h>
#include <stdio.h>

int main(void)
{
	/* Perform global initialization of the CUDA driver and
	 * prepares to manage GPU devices
	*/
	CUresult res = cuInit(0);
	if (res != CUDA_SUCCESS) {
		printf("cuInit failed with error code %d\n", res);
		return 1;
	}

	/* Find the number of cuda devices */
	int count = 0;
	cuDeviceGetCount(&count);
	if (!count) {
		printf("Could not find any cuda devices\n");
		return 1;
	}
	printf("Found %d cuda devices(s)\n", count);

	/* check device attributes */
	CUdevice dev;
	int dev_id = 0; // GPU 0
	CUcontext ctx;
	// get device handle
	res = cuDeviceGet(&dev, dev_id);
	if (res != CUDA_SUCCESS) {
		printf("cuDeviceGet failed with error code %d\n", res);
		return 1;
	}
	/* create a contrext, its like process environment, each context
		* its own GPU memory allocation table, modules, kernel launches,
		* streams and events
		*/
	res = cuCtxCreate(&ctx, NULL, 0, dev);
	if (res != CUDA_SUCCESS) {
		printf("cuCtxCtreate failed with error code %d\n", res);
		return 1;
	}

	/* Check for attribute, in this case DMABUF */
	int attribute = 0;
	res = cuDeviceGetAttribute(&attribute, CU_DEVICE_ATTRIBUTE_DMA_BUF_SUPPORTED, dev);
	if (res != CUDA_SUCCESS) {
		printf("cuCtxCtreate failed with error code %d\n", res);
		return 1;
	}
	printf("attribute: \t\t\t%s\n", attribute ? "DMABUF Supported" : "DMABUF NOT supported");

	/* check for minimum allocation granularity (page size) for a given
		* memory type and location, eg, device memory, pinned host memory,
		* system memory
		*/
	CUmemAllocationProp prop = {};
	memset(&prop, 0, sizeof(CUmemAllocationProp));
	prop.type = CU_MEM_ALLOCATION_TYPE_PINNED;
	prop.location.type = CU_MEM_LOCATION_TYPE_DEVICE;
	prop.location.id = dev_id;
	size_t gran_min, gran_rec;

	cuMemGetAllocationGranularity(&gran_min, &prop, CU_MEM_ALLOC_GRANULARITY_MINIMUM);
	cuMemGetAllocationGranularity(&gran_rec, &prop, CU_MEM_ALLOC_GRANULARITY_RECOMMENDED);
	printf("min granularity: \t\t%lu\n", gran_min);
	printf("recommended granularity: \t%lu\n", gran_rec);

	/* Reserve the virtual memory */
	size_t total_size = 64 * 1024 * 1024;
	CUdeviceptr vaddr = 0;
	total_size = ((total_size + gran_min - 1) / gran_min) * gran_min;
	res = cuMemAddressReserve(&vaddr, total_size, gran_min, 0, 0);
	if (res != CUDA_SUCCESS) {
		printf("cuMemAddressReserve failed with error code %d\n", res);
		return 1;
	}
	printf("Reserved virtual (address,size) (0x%llx, %zu)\n", (unsigned long long)vaddr, total_size);
	/* Allocate generic memory object */
	memset(&prop, 0, sizeof(CUmemAllocationProp));
	prop.type = CU_MEM_ALLOCATION_TYPE_PINNED;
	prop.location.type = CU_MEM_LOCATION_TYPE_DEVICE;
	prop.location.id = dev_id;
	prop.requestedHandleTypes = CU_MEM_HANDLE_TYPE_POSIX_FILE_DESCRIPTOR;
	CUmemGenericAllocationHandle handle;
	res = cuMemCreate(&handle, total_size, &prop, 0);
	if (res != CUDA_SUCCESS) {
		printf("cuMemCreate failed with error code %d\n", res);
		return 1;
	}
	/* Map physical memory for the GPU virtual address space */
	// CUdeviceptr phys_addr;
	res = cuMemMap(vaddr, total_size, 0, handle, 0);
	if (res != CUDA_SUCCESS) {
		printf("cuMemMap failed with error code %d\n", res);
		return 1;
	}
	// printf("Memory is succesffully mapped at GPU address: 0x%x\n", phys_addr);

	/* Get read/write access to GPU 0 */
	CUmemAccessDesc access;	
	memset(&access, 0, sizeof(CUmemAccessDesc));
	access.location.type = CU_MEM_LOCATION_TYPE_DEVICE;
	access.location.id = dev_id;
	access.flags = CU_MEM_ACCESS_FLAGS_PROT_READWRITE;
	res = cuMemSetAccess(vaddr, total_size, &access, 1);
	if (res != CUDA_SUCCESS) {
		printf("cuMemSetAccess failed with error code %d\n", res);
		return 1;
	}

	/* export GPU memory alocated vai CUDA VMM to OS-level handle */
	CUdeviceptr sub_addr = vaddr;
	size_t sub_size = 16 * 1024 * 1024;
	CUmemGenericAllocationHandle sub_handle;
	res = cuMemGetHandleForAddressRange(&sub_handle, sub_addr, sub_size,
			       CU_MEM_RANGE_HANDLE_TYPE_DMA_BUF_FD, 0);
	if (res != CUDA_SUCCESS) {
		printf("cuMemGetHandleForAddressRange failed with error code %d\n", res);
		return 1;
	}
	printf("Obtained sub-range handle, (%p, %zu)\n", (void*)sub_handle, total_size);

	// /* expor sub-range handle as an IPC handle */
	// CUipcMemHandle ipc_handle;
	// res = cuIpcGetMemHandle(&ipc_handle, sub_handle);
	// if (res != CUDA_SUCCESS) {
	// 	printf("cuIpcGetMemHandle failed with error code %d\n", res);
	// 	return 1;
	// }

	cuMemUnmap(handle, total_size); // cuMemMap
	cuMemRelease(handle); // cuMemCreate
	cuMemAddressFree(vaddr, total_size); // cuMemAddressReserve
	cuCtxDestroy(ctx); //cuCtxCreate
	return 0;
}
