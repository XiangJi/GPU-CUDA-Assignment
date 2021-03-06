#include <stdio.h>  // C standard I/O header
#include <sys/time.h> // system time
#include <cuda.h> //Defines the public host functions and types for the CUDA API
#include <cfloat> //C float.h
#include <math.h>

// The number of threads per blocks in the kernel
// (if we define it here, then we can use its value in the kernel,
//  for example to statically declare an array in shared memory)
const int threads_per_block = 256;


// Forward function declarations
float GPU_vector_max(float *A, int N, int kernel_code);
float CPU_vector_max(float *A, int N);
float *get_random_vector(int N);
float *get_increasing_vector(int N);
long long start_timer();
long long stop_timer(long long start_time, char *name);
void die(char *message);
void checkError();

int main(int argc, char **argv) {

    //default kernel
    int kernel_code = 1;
    //argc = number of arguements, argv = arguement string
    //sample arguements  vectormax 256 -k 1 [0123]
    // Parse vector length and kernel options, arguement listener
    int N;
    if(argc == 2) {
        N = atoi(argv[1]); // user-specified value
    } else if (argc == 4 && !strcmp(argv[2], "-k")) {
        N = atoi(argv[1]); // user-specified value
        kernel_code = atoi(argv[3]); 
        printf("KERNEL_CODE %d\n", kernel_code); //decimal output
    } else {
        die("USAGE: ./vector_max <vector_length> -k <kernel_code>");//otherwise promote usage
    }

    // Seed the random generator (use a constant here for repeatable results)
    srand(10);//generate seed for rand function to get random number

    // Generate a random vector
    // You can use "get_increasing_vector()" for debugging, vector with order
    long long vector_start_time = start_timer(); // longlong 64 bits variable
    float *vec = get_random_vector(N); // get random vector of N, rand() inside

    //float *vec = get_increasing_vector(N); just for debugging
    stop_timer(vector_start_time, "Vector generation");
	
    // Compute the max on the GPU
    long long GPU_start_time = start_timer();
    float result_GPU = GPU_vector_max(vec, N, kernel_code);
    long long GPU_time = stop_timer(GPU_start_time, "\t            Total");// t = tab
	
    // Compute the max on the CPU
    long long CPU_start_time = start_timer();
    float result_CPU = CPU_vector_max(vec, N);
    long long CPU_time = stop_timer(CPU_start_time, "\nCPU");
    
    // Free vector, release the memory for vec, opposite to malloc
    free(vec);

    // Compute the speedup or slowdown
    if (GPU_time > CPU_time) printf("\nCPU outperformed GPU by %.2fx\n", (float) GPU_time / (float) CPU_time);
    else                     printf("\nGPU outperformed CPU by %.2fx\n", (float) CPU_time / (float) GPU_time);
	
    // Check the correctness of the GPU result, CPU must be correct
    int wrong = result_CPU != result_GPU;
	
    // Report the correctness results
    if(wrong) printf("GPU output %f did not match CPU output %f\n", result_GPU, result_CPU);
        
}


// A GPU kernel that computes the maximum value of a vector, some as loop for computing max
// (each lead thread (threadIdx.x == 0) computes a single value, parallel kernel
__global__ void vector_max_kernel1(float *in, float *out, int N) {

    // Determine the "flattened" block id and thread id, dim3 and unit3, still number but unassigned
    int block_id = blockIdx.x + gridDim.x * blockIdx.y;
    int thread_id = blockDim.x * block_id + threadIdx.x;

    // A single "lead" thread in each block finds the maximum value over a range of size threads_per_block, only use one thread in one block
    float max = 0.0;
    if (threadIdx.x == 0) {

        //calculate out of bounds guard, vague, actually the remained threads in on block
        //our block size will be 256, but our vector may not be a multiple of 256!
        int end = threads_per_block;
        if(thread_id + threads_per_block > N)
            end = N - thread_id;

        //grab the lead thread's value, in[] is the floast of the element in vector
        max = in[thread_id];

        //grab values from all other threads' locations, obtain max in every block
        for(int i = 1; i < end; i++) {
                
            //if larger, replace
            if(max < in[thread_id + i])
                max = in[thread_id + i];
        }

        out[block_id] = max; // store every the the biggest value in all blocks

    }
}

__global__ void vector_max_kernel2(float *in, float *out, int N) {
	//allocate a shared memory in block
	__shared__ float sharedmem[threads_per_block];
    // Determine the "flattened" block id and thread id, dim3 and unit3, still number but unassigned
    int block_id = blockIdx.x + gridDim.x * blockIdx.y;
    int thread_id = blockDim.x * block_id + threadIdx.x;
	
	//copy vector to each shared memory of each block;
	sharedmem[threadIdx.x] = in[thread_id];
	__syncthreads();

    // A single "lead" thread in each block finds the maximum value over a range of size threads_per_block, only use one thread in one block
    float max = 0.0;
    if (threadIdx.x == 0) {

        //calculate out of bounds guard, vague, actually the remained threads in on block
        //our block size will be 256, but our vector may not be a multiple of 256!
        int end = threads_per_block;
        if(thread_id + threads_per_block > N)
            end = N - thread_id;

        //grab the lead thread's value, in[] is the floast of the element in vector
        max = sharedmem[threadIdx.x];

        //grab values from all other threads' locations, obtain max in every block
        for(int i = 1; i < end; i++) {
                
            //always
            if(max < sharedmem[threadIdx.x + i])
                max = sharedmem[threadIdx.x + i];
        }

        out[block_id] = max; // store every the the biggest value in all blocks

    }
}


__global__ void vector_max_kernel3(float *in, float *out, int N) {
	//allocate a shared memory in block
	__shared__ float sharedmem[threads_per_block];
	__shared__ int end;
    // Determine the "flattened" block id and thread id, dim3 and unit3, still number but unassigned
    int block_id = blockIdx.x + gridDim.x * blockIdx.y;
    int thread_id = blockDim.x * block_id + threadIdx.x;
	
	sharedmem[threadIdx.x] = 0;
	//copy vector to each shared memory of each block;
	sharedmem[threadIdx.x] = in[thread_id];
	__syncthreads();

    // A single "lead" thread in each block finds the maximum value over a range of size threads_per_block, only use one thread in one block
    if (threadIdx.x == 0) {
        //calculate out of bounds guard, vague, actually the remained threads in on block
        //our block size will be 256, but our vector may not be a multiple of 256!
        end = threads_per_block;
        if(thread_id + threads_per_block > N)
            end = N - thread_id;
		if(end % 2 != 0)
			end += 1;
	}
	__syncthreads();
	
	 //grab values from all other threads' locations, obtain max in every block
    for(int i = 1; i < end; i = i * 2) {
		if (threadIdx.x % (2 * i) == 0) {
			//alway put bigger one in the lower position, step times 2 every iteration
            if(sharedmem[threadIdx.x] < sharedmem[threadIdx.x + i])
                sharedmem[threadIdx.x] = sharedmem[threadIdx.x + i];
		}
		__syncthreads();
    }
		
	if (threadIdx.x == 0)
		out[block_id] = sharedmem[0]; // put the max one in [0] for outblock
	
}
//group useful threads
__global__ void vector_max_kernel4(float *in, float *out, int N) {
	//allocate a shared memory in block
	__shared__ float sharedmem[threads_per_block];
	__shared__ int end;
    // Determine the "flattened" block id and thread id, dim3 and unit3, still number but unassigned
    int block_id = blockIdx.x + gridDim.x * blockIdx.y;
    int thread_id = blockDim.x * block_id + threadIdx.x;
	
	sharedmem[threadIdx.x] = 0;
	//copy vector to each shared memory of each block;
	sharedmem[threadIdx.x] = in[thread_id];
	__syncthreads();

    // A single "lead" thread in each block finds the maximum value over a range of size threads_per_block, only use one thread in one block
    if (threadIdx.x == 0) {
        //calculate out of bounds guard, vague, actually the remained threads in on block
        //our block size will be 256, but our vector may not be a multiple of 256!
        end = threads_per_block;
        if(thread_id + threads_per_block > N)
            end = N - thread_id;
		
		end = (int)powf(2, ceilf(log2f((float)end)));
	}
	__syncthreads();
	
	int tblock = end; 
	while (tblock > 1){
		if (threadIdx.x < tblock / 2) {
			if(sharedmem[threadIdx.x] < sharedmem[threadIdx.x + tblock/2])
				sharedmem[threadIdx.x] = sharedmem[threadIdx.x + tblock/2];
		}
		tblock /= 2;
		__syncthreads();
    }
		
	if (threadIdx.x == 0)
		out[block_id] = sharedmem[0]; // put the max one in [0] for outblock
	
}



// Returns the maximum value within a vector of length N, use GPU method
float GPU_vector_max(float *in_CPU, int N, int kernel_code) {

    int vector_size = N * sizeof(float);//size of float

    // Allocate CPU memory for the result, give OUT_CPU space
    float *out_CPU = (float *) malloc(vector_size);
    if (out_CPU == NULL) die("Error allocating CPU memory");

    // Allocate GPU memory for the inputs and the result
    long long memory_start_time = start_timer();

    float *in_GPU, *out_GPU;// the threads vector and the block vector
    if (cudaMalloc((void **) &in_GPU, vector_size) != cudaSuccess) die("Error allocating GPU memory");
    if (cudaMalloc((void **) &out_GPU, vector_size) != cudaSuccess) die("Error allocating GPU memory");
    //cudaSuccess is a error variable which record the error
    //cudaPeekAtLastError() returns this variable. cudaGetLastError() returns this variable and resets it to cudaSuccess

    // Transfer the input vectors to GPU memory
    cudaMemcpy(in_GPU, in_CPU, vector_size, cudaMemcpyHostToDevice);// dst, src, size, kind
    cudaDeviceSynchronize();  //synchronize just after the call, check for asynchronous errors, here only timing purpose
    stop_timer(memory_start_time, "\nGPU:\t  Transfer to GPU");// transfer time

    bool lastBlock = 0;
    while (!lastBlock) {
        // Determine the number of thread blocks in the x- and y-dimension
        int num_blocks = (int) ((float) (N + threads_per_block - 1) / (float) threads_per_block);
        int max_blocks_per_dimension = 65535;
        int num_blocks_y = (int) ((float) (num_blocks + max_blocks_per_dimension - 1) / (float) max_blocks_per_dimension);
        int num_blocks_x = (int) ((float) (num_blocks + num_blocks_y - 1) / (float) num_blocks_y);
        dim3 grid_size(num_blocks_x, num_blocks_y, 1);

        // Execute the kernel to compute the vector sum on the GPU
        long long kernel_start_time;
        kernel_start_time = start_timer();

        switch(kernel_code){
        case 1 :
            vector_max_kernel1 <<< grid_size , threads_per_block >>> (in_GPU, out_GPU, N);
            break;
        case 2 :
            vector_max_kernel2 <<< grid_size , threads_per_block >>> (in_GPU, out_GPU, N);
            break;
        case 3 :
            vector_max_kernel3 <<< grid_size , threads_per_block >>> (in_GPU, out_GPU, N);
            break;
        case 4 :
            //LAUNCH KERNEL FROM PROBLEM 4 HERE
            vector_max_kernel4 <<< grid_size , threads_per_block >>> (in_GPU, out_GPU, N);
            break;
        default :
            die("INVALID KERNEL CODE\n");
        }

        if (num_blocks > 1) {
            lastBlock = 0;
            N = num_blocks;
            cudaMemcpy(in_GPU, out_GPU, vector_size, cudaMemcpyDeviceToDevice);
            cudaDeviceSynchronize();
        }
        else {
            lastBlock = 1;
        }

        cudaDeviceSynchronize();  // this is only needed for timing purposes
        stop_timer(kernel_start_time, "\t Kernel execution");

        checkError();
    }
    



    // Transfer the result from the GPU to the CPU
    memory_start_time = start_timer();
    
    //copy C back from GPU device to CPU
    cudaMemcpy(out_CPU, out_GPU, vector_size, cudaMemcpyDeviceToHost);
    checkError();
    cudaDeviceSynchronize();  // this is only needed for timing purposes
    stop_timer(memory_start_time, "\tTransfer from GPU");
    			    
    // Free the GPU memory
    cudaFree(in_GPU);
    cudaFree(out_GPU);

    float max = out_CPU[0];
    free(out_CPU);

    //return a single statistic, max in vector
    return max;
}


// Returns the maximum value within a vector of length N, just CPU simple MAX function
float CPU_vector_max(float *vec, int N) {	

    // find the max
    float max;
    max = vec[0];
    for (int i = 1; i < N; i++) {
        if(max < vec[i]) {
            max = vec[i];
        }
    }
	
    // Return a single statistic
    return max;
}


// Returns a randomized vector containing N elements, vector generator
float *get_random_vector(int N) {
    if (N < 1) die("Number of elements must be greater than zero");
	
    // Allocate memory for the vector, memory size N float, malloc
    float *V = (float *) malloc(N * sizeof(float));
    if (V == NULL) die("Error allocating CPU memory");
	
    // Populate the vector with random numbers
    for (int i = 0; i < N; i++) V[i] = (float) rand() / (float) rand();
	
    // Return the randomized vector, float *V
    return V;
}

float *get_increasing_vector(int N) {
    if (N < 1) die("Number of elements must be greater than zero");
	
    // Allocate memory for the vector
    float *V = (float *) malloc(N * sizeof(float));
    if (V == NULL) die("Error allocating CPU memory");
	
    // Populate the vector with random numbers, number fixed 1, 2, 3...
    for (int i = 0; i < N; i++) V[i] = (float) i;
	
    // Return the randomized vector
    return V;
}

//use it for debug kernel
void checkError() {
    // Check for kernel errors, based on cuda lib
    cudaError_t error = cudaGetLastError();
    if (error) {
        char message[256];
        sprintf(message, "CUDA error: %s", cudaGetErrorString(error));
        die(message);
    }
}

// Returns the current time in microseconds, (us)
//int gettimeofday (struct timeval *tv, struct timezone *tz)
long long start_timer() {
    struct timeval tv;
    gettimeofday(&tv, NULL);
    return tv.tv_sec * 1000000 + tv.tv_usec;
}


// Prints the time elapsed since the specified time, print and return the time interval
long long stop_timer(long long start_time, char *name) {
    struct timeval tv;
    gettimeofday(&tv, NULL);
    long long end_time = tv.tv_sec * 1000000 + tv.tv_usec;
    printf("%s: %.5f sec\n", name, ((float) (end_time - start_time)) / (1000 * 1000));
    return end_time - start_time;
}


// Prints the specified message and quits
void die(char *message) {
    printf("%s\n", message);
    exit(1); 
}
