#include <stdlib.h>
#include <stdio.h>
#include <math.h>
#include <time.h>
#include <cuda_runtime.h>
#include <cublas_v2.h>
#include <cusparse.h>

#include "../include/CuCG.h"

//#include "../include/my_crs_matrix.h"
#define PRECI_DT double 
#define PRECI_S "%lf "
#define PRECI_CUDA CUDA_R_64F

typedef struct {
  cusparseDnVecDescr_t desc;
  PRECI_DT*            val;
} my_cuda_vector;

typedef struct {
  cusparseSpMatDescr_t desc;
  int n;
  int m;
  int nz;
  PRECI_DT *val;
  int *col;
  int *rowptr;
} my_cuda_csr_matrix;

__host__ void cusparse_conjugate_gradient(my_cuda_csr_matrix *A,
					  my_cuda_csr_matrix *M,
					  my_cuda_vector *b,
					  my_cuda_vector *x,
					  int max_iter,
					 PRECI_DT tolerance,
					  cusparseHandle_t* handle,
					  cublasHandle_t* handle_blas)

{
  int n = A->n;
  size_t pitch;
  // Make r vector
  my_cuda_vector *r_vec = (my_cuda_vector*)malloc(sizeof(my_cuda_vector));
  PRECI_DT* h_r = (PRECI_DT*)malloc(sizeof(PRECI_DT)*n);
  for(int i=0;i<n;i++) h_r[i] = 1;
  cudaMallocPitch((void**)&r_vec->val,&pitch, n * sizeof(PRECI_DT), 1);
  cudaMemcpy(r_vec->val, h_r, n * sizeof(PRECI_DT), cudaMemcpyHostToDevice);
  cusparseCreateDnVec(&r_vec->desc, n, r_vec->val,PRECI_CUDA);

  // Make p vector
  my_cuda_vector *p_vec = (my_cuda_vector*)malloc(sizeof(my_cuda_vector));
  PRECI_DT* h_p = (PRECI_DT*)malloc(sizeof(PRECI_DT)*n);
  for(int i=0;i<n;i++) h_p[i] = 1;
  cudaMallocPitch((void**)&p_vec->val,&pitch, n * sizeof(PRECI_DT),1);
  cudaMemcpy(p_vec->val, h_p, n * sizeof(PRECI_DT), cudaMemcpyHostToDevice);
  cusparseCreateDnVec(&p_vec->desc, n, p_vec->val,PRECI_CUDA);

  // Make q vector
  my_cuda_vector *q_vec = (my_cuda_vector*)malloc(sizeof(my_cuda_vector));
  PRECI_DT* h_q = (PRECI_DT*)malloc(sizeof(PRECI_DT)*n);
  for(int i=0;i<n;i++) h_q[i] = 1;
  cudaMallocPitch((void**)&q_vec->val,&pitch, n * sizeof(PRECI_DT),1);
  cudaMemcpy(q_vec->val, h_q, n * sizeof(PRECI_DT), cudaMemcpyHostToDevice);
  cusparseCreateDnVec(&q_vec->desc, n, q_vec->val,PRECI_CUDA);

  // Make z vector
  my_cuda_vector *z_vec = (my_cuda_vector*)malloc(sizeof(my_cuda_vector));
  PRECI_DT* h_z = (PRECI_DT*)malloc(sizeof(PRECI_DT)*n);
  for(int i=0;i<n;i++) h_z[i] = 1;
  cudaMallocPitch((void**)&z_vec->val,&pitch, n * sizeof(PRECI_DT),1);
  cudaMemcpy(z_vec->val, h_z, n * sizeof(PRECI_DT), cudaMemcpyHostToDevice);
  cusparseCreateDnVec(&z_vec->desc, n, z_vec->val,PRECI_CUDA);

  cublasStatus_t sb;
  
  PRECI_DT alpha = 0.0;
  PRECI_DT beta = 0.0;
  const double ne_one = -1.0;
  const double n_one = 1.0;
  const double one = 0.0;

  int iter = 0;

  PRECI_DT v = 0;
  PRECI_DT Rho = 0;
  PRECI_DT Rtmp = 0;

  PRECI_DT res_norm = 0;
  PRECI_DT init_norm = 0;
  PRECI_DT ratio = 0;

  PRECI_DT* onex = (PRECI_DT*)malloc(sizeof(PRECI_DT)*n);
  PRECI_DT* onez = (PRECI_DT*)malloc(sizeof(PRECI_DT)*n);
  PRECI_DT* oner = (PRECI_DT*)malloc(sizeof(PRECI_DT)*n);
  PRECI_DT* oneq = (PRECI_DT*)malloc(sizeof(PRECI_DT)*n);
  PRECI_DT* onep = (PRECI_DT*)malloc(sizeof(PRECI_DT)*n);
  
  double Tiny = 0.1e-28;
  double minus_alpha = 0.0;

  // x is already zero
  
  size_t bufferSizeMV;
  void* buff;
  cusparseSpMV_bufferSize(*handle,CUSPARSE_OPERATION_NON_TRANSPOSE, &n_one, A->desc, b->desc, &one, x->desc, PRECI_CUDA, CUSPARSE_MV_ALG_DEFAULT, &bufferSizeMV);
  cudaMalloc(&buff, bufferSizeMV);


  /*cudaMemcpy(onex, x->val, n * sizeof(PRECI_DT), cudaMemcpyDeviceToHost);
  cudaMemcpy(onep, p_vec->val, n * sizeof(PRECI_DT), cudaMemcpyDeviceToHost);
  cudaMemcpy(oneq, q_vec->val, n * sizeof(PRECI_DT), cudaMemcpyDeviceToHost);
  cudaMemcpy(oner, r_vec->val, n * sizeof(PRECI_DT), cudaMemcpyDeviceToHost);
  cudaMemcpy(onez, z_vec->val, n * sizeof(PRECI_DT), cudaMemcpyDeviceToHost);
  printf("\INITIAL VEC CREATION\n x1 = %lf \t alpha= %lf \t beta= %lf "
	 "\n v "
	 "= %lf\nr0 = %lf \n p0 = %lf\n q0 = %lf\n z0 = %lf\n if (norm "
	 "ratio(%lf) > tolerance(%lf)\n\n\n",
	 iter, onex[0], alpha, beta, v, oner[0], onep[0], oneq[0], onez[0], ratio,
	 tolerance);*/


  //matvec(A,x,r);
  cusparseSpMV(*handle,
	       CUSPARSE_OPERATION_NON_TRANSPOSE,//operation
	       &n_one,//alpha
	       A->desc,//matrix
	       x->desc,//vector
	       &one,//beta
	       r_vec->desc,//answer
	       PRECI_CUDA,//data type
	       CUSPARSE_MV_ALG_DEFAULT,//algorithm
	       buff//buffer
	       );
  cudaDeviceSynchronize();





  // r = b - r
  cublasDaxpy(*handle_blas, n, &ne_one, r_vec->val, 1, b->val, 1);
  cudaDeviceSynchronize();
  cublasDcopy(*handle_blas,n,b->val, 1, r_vec->val, 1);
  cudaDeviceSynchronize();

  // z = r
  cublasDcopy(*handle_blas,n,r_vec->val, 1, z_vec->val, 1);
  cudaDeviceSynchronize();

  // p = z
  cublasDcopy(*handle_blas,n,z_vec->val, 1, p_vec->val, 1);
  cudaDeviceSynchronize();
  cublasDnrm2(*handle_blas, n, r_vec->val, 1, &res_norm);
  cudaDeviceSynchronize();
  init_norm = res_norm;
  ratio = 1.0;

  cudaMemcpy(onex, x->val, n * sizeof(PRECI_DT), cudaMemcpyDeviceToHost);
  cudaMemcpy(onep, p_vec->val, n * sizeof(PRECI_DT), cudaMemcpyDeviceToHost);
  cudaMemcpy(oneq, q_vec->val, n * sizeof(PRECI_DT), cudaMemcpyDeviceToHost);
  cudaMemcpy(oner, r_vec->val, n * sizeof(PRECI_DT), cudaMemcpyDeviceToHost);

  cudaMemcpy(onez, z_vec->val, n * sizeof(PRECI_DT), cudaMemcpyDeviceToHost);
  printf("PREQUEL \n x1 = %lf \t alpha= %lf \t beta= %lf "
	 "\n v "
	 "= %lf\nr0 = %lf \n p0 = %lf\n q0 = %lf\n z0 = %lf\n if (norm "
	 "ratio(%lf) > tolerance(%e)\n\n\n",
	 iter, onex[0], alpha, beta, v, oner[0], onep[0], oneq[0], onez[0], ratio,
	 tolerance);

  while (iter <= max_iter && ratio > tolerance)
    {
      //printf("Iteration : %d",iter);
      iter++;

      // z = r
      cublasDcopy(*handle_blas,n,r_vec->val, 1, z_vec->val, 1);
      cudaDeviceSynchronize();

      // Rho = r z dot prod
      cublasDdot(*handle_blas, n, r_vec->val, 1, z_vec->val, 1, &Rho);
      cudaDeviceSynchronize();

      if (iter == 1)
	{
	  sb = cublasDcopy(*handle_blas,n,z_vec->val, 1, p_vec->val, 1);
	  cudaDeviceSynchronize();
	}
      else
	{
beta = Rho / (v + Tiny);
	    // p = z + (beta * p)
		// CHECK THIS!
	    sb = cublasDaxpy(*handle_blas, n, &alpha, p_vec->val, 1, z_vec->val, 1);
	    cudaDeviceSynchronize();
	  }

	cusparseSpMV_bufferSize(*handle,CUSPARSE_OPERATION_NON_TRANSPOSE, &n_one, A->desc, p_vec->desc, &one, q_vec->desc, PRECI_CUDA, CUSPARSE_MV_ALG_DEFAULT, &bufferSizeMV);
	cudaMalloc(&buff, bufferSizeMV);

	cusparseSpMV(*handle,
		     CUSPARSE_OPERATION_NON_TRANSPOSE,//operation
		     &n_one,//alpha
		     A->desc,//matrix
		     p_vec->desc,//vector
		     &one,//beta
		     q_vec->desc,//answer
		     PRECI_CUDA,//data type
		     CUSPARSE_MV_ALG_DEFAULT,//algorithm
		     buff//buffer
		     );
	cudaDeviceSynchronize();
  
	// Rtmp = p q dot prod
	cublasDdot(*handle_blas, n, p_vec->val, 1, q_vec->val, 1, &Rtmp);
	cudaDeviceSynchronize();

	// v = r z dot prod
	cublasDdot(*handle_blas, n, r_vec->val, 1, z_vec->val, 1, &v);
	cudaDeviceSynchronize();

	//alpha
	alpha = Rho / (Rtmp + Tiny);
  
	// x = x + alpha * p
	cublasDaxpy(*handle_blas, n, &alpha, p_vec->val, 1, x->val, 1);

	cudaDeviceSynchronize();

	// r = r - alpha * q
	minus_alpha = -alpha;
	cublasDaxpy(*handle_blas, n, &alpha,q_vec->val,1,r_vec->val,1);
	cudaDeviceSynchronize();

	Rho = 0.0;
	cublasDnrm2(*handle_blas, n, r_vec->val, 1, &res_norm);
	cudaDeviceSynchronize();

	ratio = res_norm/init_norm;

	if (iter > 0) {
		// A*x=r
	  cusparseSpMV_bufferSize(*handle,CUSPARSE_OPERATION_NON_TRANSPOSE, &n_one, A->desc, x->desc, &one, r_vec->desc, PRECI_CUDA, CUSPARSE_MV_ALG_DEFAULT, &bufferSizeMV);
	  cudaMalloc(&buff, bufferSizeMV);
	  cusparseSpMV(*handle,
		       CUSPARSE_OPERATION_NON_TRANSPOSE,//operation
		       &n_one,//alpha
		       A->desc,//matrix
		       x->desc,//vector
		       &one,//beta
		       r_vec->desc,//answer
		       PRECI_CUDA,//data type
		       CUSPARSE_MV_ALG_DEFAULT,//algorithm
		       buff//buffer
		       );
	  cudaDeviceSynchronize();
	//r = b - r
	  cublasDaxpy(*handle_blas, n, &ne_one, b->val, 1, r_vec->val, 1);
	  cudaDeviceSynchronize();

	}

	cudaDeviceSynchronize();
	int error = cudaGetLastError();
	printf("\n%s - %s\n", cudaGetErrorName(error), cudaGetErrorString(error));
	cudaMemcpy(onex, x->val, n * sizeof(PRECI_DT), cudaMemcpyDeviceToHost);
	cudaMemcpy(onep, p_vec->val, n * sizeof(PRECI_DT), cudaMemcpyDeviceToHost);
	cudaMemcpy(oneq, q_vec->val, n * sizeof(PRECI_DT), cudaMemcpyDeviceToHost);
	cudaMemcpy(oner, r_vec->val, n * sizeof(PRECI_DT), cudaMemcpyDeviceToHost);
	cudaMemcpy(onez, z_vec->val, n * sizeof(PRECI_DT), cudaMemcpyDeviceToHost);
	printf("\nend of iteration %d\n x1 = %lf \t alpha= %lf \t beta= %lf \t res_norm = %lf"
	       "\n v "
	       "= %lf\nr0 = %lf \n p0 = %lf\n q0 = %lf\n z0 = %lf\n if (norm "
	       "ratio(%lf) > tolerance(%lf)\n\n\n",
	       iter, onex[0], alpha, beta, res_norm, v, oner[0], onep[0], oneq[0], onez[0], ratio,
	       tolerance);

	//printf("\e[1;1H\e[2J");
      }

  // free everything
    cudaFree(p_vec->val);
    cusparseDestroyDnVec(p_vec->desc);
    free(p_vec);

    cudaFree(z_vec->val);
    cusparseDestroyDnVec(z_vec->desc);
    free(z_vec);

    cudaFree(q_vec->val);
    cusparseDestroyDnVec(q_vec->desc);
    free(q_vec);

    cudaFree(r_vec->val);
    cusparseDestroyDnVec(r_vec->desc);
    free(r_vec);
    return;
}


__host__ my_cuda_csr_matrix* cusparse_crs_read(char* name)
{
  my_cuda_csr_matrix *M = (my_cuda_csr_matrix*)malloc(sizeof(my_cuda_csr_matrix));
  PRECI_DT* val;
  int* col;
  int* rowptr;

  int n = 0;
  int m = 0;
  int nz = 0;
  FILE *file;
  if ((file = fopen(name, "r"))) {
    int i;

    fscanf(file, "%d %d %d", &m, &n, &nz);

    /*PRECI_DT* val = new PRECI_DT[nz];
      int* col = new int[nz];
      int* rowptr = new int[n];*/

    val = (PRECI_DT*)malloc(sizeof(PRECI_DT)*nz);

    col = (int*)malloc(sizeof(int)*nz);
    rowptr = (int*)malloc(sizeof(int)*n+1);
    

    for (i = 0; i <= n; i++)
      fscanf(file, "%d ", &rowptr[i]);
    for (i = 0; i < nz; i++)
      fscanf(file, "%d ", &col[i]);
    for (i = 0; i < nz; i++)
      fscanf(file, PRECI_S, &val[i]);

/*    printf("rowptr : ");

    for( i = 0; i <= n; i++)
      printf("%d, ",rowptr[i]);
    printf("\n");


    printf("col : ");

    for( i = 0; i < nz; i++)
      printf("%d, ",col[i]);
    printf("\n");

    printf("val : ");

    for( i = 0; i < nz; i++)
      printf("%lf, ",val[i]);
    printf("\n");*/

    fclose(file);
    size_t pitch;
    // Allocate memory for the CSR matrix
    cudaMallocPitch((void**)&M->rowptr,&pitch, (n+1) * sizeof(int),1);
    cudaMallocPitch((void**)&M->col,&pitch, nz * sizeof(int),1);
    cudaMallocPitch((void**)&M->val,&pitch, nz * sizeof(PRECI_DT),1);


    // Copy data from host to device
    cudaMemcpy(M->rowptr, rowptr, (n+1) * sizeof(int), cudaMemcpyHostToDevice);
    cudaMemcpy(M->col, col, nz * sizeof(int), cudaMemcpyHostToDevice);
    cudaMemcpy(M->val, val, nz * sizeof(PRECI_DT), cudaMemcpyHostToDevice);

    M->n = n;
    M->m = m;
    M->nz = nz;
    cusparseCreateCsr(&M->desc, n, n, nz, M->rowptr, M->col, M->val, CUSPARSE_INDEX_32I, CUSPARSE_INDEX_32I, CUSPARSE_INDEX_BASE_ZERO, PRECI_CUDA);
    //Create the CSR matrix
   
  } else {
    printf("ERROR: could not open file %s\n", name);
    n = -1;
  }
  return M;
}


void call_CuCG(char* name, PRECI_DT* h_b, PRECI_DT* h_x, int maxit, PRECI_DT tol)
{
  //printf("Creating cusparse handle!\n");
  cublasHandle_t cublasHandle;
  cublasCreate(&cublasHandle);
  cusparseHandle_t cusparseHandle;
  cusparseStatus_t status = cusparseCreate(&cusparseHandle);
  if (status != CUSPARSE_STATUS_SUCCESS)
  {
    printf("Error creating cusparse Handle!\n"); 
  }
  else
    {
      size_t pitch;
      //printf("reading matrix file...\n");
      my_cuda_csr_matrix *A_matrix = cusparse_crs_read((char*)name);

      int64_t n=A_matrix->n;

      //printf("creating vectors... %d",A_matrix->n);

      // Make x vector
      my_cuda_vector *x_vec = (my_cuda_vector*)malloc(sizeof(my_cuda_vector));
      //PRECI_DT* h_x = (PRECI_DT*)malloc(sizeof(PRECI_DT)*n);
      for(int i=0;i<n;i++) h_x[i] = 0;
      cudaMallocPitch((void**)&x_vec->val,&pitch, n * sizeof(PRECI_DT),1);
      cudaMemcpy(x_vec->val, h_x, n * sizeof(PRECI_DT), cudaMemcpyHostToDevice);
      cusparseCreateDnVec(&x_vec->desc, n, x_vec->val,PRECI_CUDA);

      // Make b vector
      my_cuda_vector *b_vec = (my_cuda_vector*)malloc(sizeof(my_cuda_vector));
      //PRECI_DT* h_b = (PRECI_DT*)malloc(sizeof(PRECI_DT)*n);
      //for(int i=0;i<n;i++) h_b[i] = 1;
      cudaMallocPitch((void**)&b_vec->val, &pitch, n * sizeof(PRECI_DT),1);
      cudaMemcpy(b_vec->val, h_b, n * sizeof(PRECI_DT), cudaMemcpyHostToDevice);
      cusparseCreateDnVec(&b_vec->desc, n, b_vec->val,PRECI_CUDA);

      /*printf("Created Vectors!\n");  

      for (int i = 0; i < 10; i++)
	printf(PRECI_S,h_x[i]);
      printf("\n");*/

      /*for (int i = 0; i < 10; i++)
	printf(PRECI_S,h_b[i]);
      printf("\n");*/

      //printf("Calling CG func...");
      cusparse_conjugate_gradient(A_matrix, A_matrix, b_vec,x_vec,maxit,tol, &cusparseHandle, &cublasHandle);
      //printf("Done!\n");

      cudaMemcpy(h_x, x_vec->val, n * sizeof(PRECI_DT), cudaMemcpyDeviceToHost);
      cudaMemcpy(h_b, b_vec->val, n * sizeof(PRECI_DT), cudaMemcpyDeviceToHost);

      /*for (int i = 0; i < 10; i++)
	 printf(PRECI_S,h_x[i]);
       printf("\n");

       for (int i = 0; i < 10; i++)
	 printf(PRECI_S,h_b[i]);
      printf("\n");*/

      cusparseDestroySpMat(A_matrix->desc);
      cudaFree(A_matrix->val);
      cudaFree(A_matrix->rowptr);
      cudaFree(A_matrix->col);
      free(A_matrix);

      cudaFree(x_vec->val);
      cusparseDestroyDnVec(x_vec->desc);
      free(x_vec);

      cudaFree(b_vec->val);
      cusparseDestroyDnVec(b_vec->desc);
      free(b_vec);

      cusparseDestroy(cusparseHandle);
      cublasDestroy(cublasHandle);

    }
  //printf("Done!\n");

  
    
  return;
}

/*int main (void)
  {
  call_CuCG();
  return 0;
  }*/
