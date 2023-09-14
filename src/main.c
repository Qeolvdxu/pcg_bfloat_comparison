#define _DEFAULT_SOURCE

#include <dirent.h>
#include <pthread.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

#include "../include/CCG.h"
#include "../include/CuCG.h"
#include "../include/my_crs_matrix.h"
#include "../include/trisolv.h"

#define CPU_EXECUTION 0
#define GPU_EXECUTION 1

// call_CuCG(files[i],b,x,maxit,tol);

typedef struct {
  char precond;
  char concurrent;
  char *name;
  char *pname;
  int matrix_count;
  char **files;
  char **pfiles;
  int maxit;
  double tol;
} Data_CG;

typedef struct {
  Data_CG *data;
  int executionTarget;
} ThreadArgs;


char **find_files(const char *dir_path, int *num_files) {
  printf("DIR = %s\n", dir_path);
  DIR *dir = opendir(dir_path);
  struct dirent *entry;
  char **files = NULL;
  int count = 0;
  int i, j;
  char *temp;
  if (dir == NULL) {
    perror("opendir");
    return NULL;
  }

  while ((entry = readdir(dir)) != NULL) {
    if (entry->d_type == DT_REG) {
      files = (char **)realloc(files, sizeof(char *) * (count + 1));
      files[count] =
          (char *)malloc(strlen(dir_path) + strlen(entry->d_name) + 2);
      sprintf(files[count], "%s/%s", dir_path, entry->d_name);
      count++;
    }
  }

  closedir(dir);

  for (i = 0; i < count - 1; i++) {
    for (j = 0; j < count - i - 1; j++) {
      if (strcmp(files[j], files[j + 1]) > 0) {
        temp = files[j];
        files[j] = files[j + 1];
        files[j + 1] = temp;
      }
    }
  }

  *num_files = count;

  return files;
}



// Function to read the configuration from a config.ini file
int readConfigFile(Data_CG *data, const char *configFileName) {
  printf("test 1");
  FILE *configFile = fopen(configFileName, "r");
  if (configFile == NULL) {
    perror("Failed to open configuration file");
    return 0;
  }

  // Initialize default values
  data->precond = 'N';
  data->concurrent = 'N';
  data->name = NULL;
  data->pname = NULL;
  data->tol = 1e-7;
  data->maxit = 10000;

  char line[256];
  while (fgets(line, sizeof(line), configFile)) {
    char key[64], value[256];
    if (sscanf(line, "%63s = %255s", key, value) == 2) {
      if (strcmp(key, "precond") == 0) {
        data->precond = value[0];
      } else if (strcmp(key, "concurrent") == 0) {
        data->concurrent = value[0];
      } else if (strcmp(key, "name") == 0) {
        data->name = strdup(value);
      } else if (strcmp(key, "pname") == 0) {
        data->pname = strdup(value);
      } else if (strcmp(key, "tol") == 0) {
        data->tol = atof(value);
      } else if (strcmp(key, "maxit") == 0) {
        data->maxit = atoi(value);
      }
    }
  }

  fclose(configFile);
  return 1;
}


void *batch_CG(void *arg) {
  ThreadArgs *threadArgs = (ThreadArgs *)arg;
  Data_CG *data = threadArgs->data;
  int executionTarget = threadArgs->executionTarget;
  const char *outputFileName;

  if (executionTarget == CPU_EXECUTION) {
    outputFileName = "../Data/results_CCG_TEST.csv";
  } else if (executionTarget == GPU_EXECUTION) {
    outputFileName = "../Data/results_CudaCG_TEST.csv";
  } else {
    printf("Invalid execution target!\n");
    return NULL;
  }

  FILE *ofile = fopen(outputFileName, "w");
  int k = -1; // error location
  int i, j, q;
  double *x;
  double *b;
  int iter;
  double k_twonrm = -1.0;
  double elapsed = 0.0;
  double fault_elapsed = 0.0;
  double mem_elapsed = 0.0;
const char *firstDot;
const char *lastSlash;
  for (j = 0; j < 1; j++) {
    for (i = 0; i < data->matrix_count; i++) {
      elapsed = 0.0;
      fault_elapsed = 0.0;
      mem_elapsed = 0.0;
      // Create Matrix struct and Precond
      my_crs_matrix *A = my_crs_read(data->files[i]);
#ifdef INJECT_ERROR
      k = rand() % A->n;
      k_twonrm = sp2nrmrow(k, A->n, A->rowptr, A->val);
#endif

      my_crs_matrix *M;
      if (data->pfiles)
        M = my_crs_read(data->pfiles[i]);

      // allocate arrays
      x = calloc(A->n, sizeof(double));
      b = malloc(sizeof(double) * A->n);
      for (q = 0; q < A->n; q++)
        b[q] = 1;
     lastSlash= strrchr(data->files[i], '/');
    firstDot = strchr(lastSlash, '.');

      printf("%s CG : %.*s", (executionTarget == CPU_EXECUTION) ? "CPU" : "GPU", (int)(firstDot - lastSlash - 1), lastSlash + 1);
      if (data->pfiles) {
        printf(" with preconditioning\n", data->pfiles[i]);
        if (executionTarget == CPU_EXECUTION) {
          CCG(A, M, b, x, data->maxit, data->tol, &iter, &elapsed, &fault_elapsed, k);
        } else if (executionTarget == GPU_EXECUTION) {
          call_CuCG(data->files[i], data->pfiles[i], b, x, data->maxit, (double)data->tol, &iter, &elapsed, &mem_elapsed, &fault_elapsed, k);
        }
      } else {
        printf("\n");
        if (executionTarget == CPU_EXECUTION) {
          CCG(A, NULL, b, x, data->maxit, data->tol, &iter, &elapsed, &fault_elapsed, k);
        } else if (executionTarget == GPU_EXECUTION) {
          call_CuCG(data->files[i], NULL, b, x, data->maxit, (double)data->tol, &iter, &elapsed, &mem_elapsed, &fault_elapsed, k);
        }
      }

      if (iter == 0)
        return NULL;

      elapsed -= fault_elapsed;

      if (j == 0 && i == 0)
        fprintf(ofile, "DEVICE,MATRIX,PRECISION,ITERATIONS,WALL_TIME,MEM_WALL_"
                       "TIME,FAULT_TIME,INJECT_SITE,ROW_2-NORM,"
                       "X_VECTOR\n");
      if (executionTarget == CPU_EXECUTION) fprintf(ofile, "CPU,");
      else if (executionTarget == GPU_EXECUTION) fprintf(ofile, "GPU,");
      fprintf(ofile, "%.*s,", (int)(firstDot - lastSlash - 1), lastSlash + 1);
      fprintf(ofile, "%s,%d,%lf,%lf,%lf,%d,%lf,", "double", iter, elapsed, mem_elapsed,
              fault_elapsed, k, k_twonrm);
      /*printf("cpu time : %s,%d,%lf,%d,%lf \n", "double", iter, elapsed, 0,
             fault_elapsed);*/
      // printf("TOTAL C ITERATIONS: %d", iter);
      for (q = 0; q < 5; q++) {
        fprintf(ofile, "%0.10lf,", x[q]);
        // printf("%0.10lf,", x[q]);
      }
      fprintf(ofile, "\n");

      my_crs_free(A);
      if (data->pfiles)
        my_crs_free(M);
      free(b);
      free(x);

      if (executionTarget == CPU_EXECUTION) printf("CPU ");
      else if (executionTarget == GPU_EXECUTION) printf("GPU ");
      printf("CG : Test %d complete in %d iterations!\n", i, iter);
      // Rest of your batch processing logic...

    }
    printf("\t %s BATCH %d FINISHED!\n", (executionTarget == CPU_EXECUTION) ? "CPU" : "GPU", j);
  }
  printf("\t\t %s FULLY COMPLETE!\n", (executionTarget == CPU_EXECUTION) ? "CPU" : "GPU");
  fclose(ofile);
  return NULL;
}

int main(int argc, char *argv[]) {
  srand(time(0));

  // Set initial values
  int i = 0;
  pthread_t th1;
  pthread_t th2;
  Data_CG *data;

  data = malloc(sizeof(Data_CG));

  if (!readConfigFile(data, "../config.ini")) {
    return 1;
  }

  data->files = find_files(data->name, &data->matrix_count);
  int matrix_count = data->matrix_count;
  int precond_count = data->precond == 'Y' ? matrix_count : 0;

  if (matrix_count != precond_count && data->precond == 'Y') {
    printf("ERROR: number of matrices (%d) and preconditioners (%d) do not match!\n",
           matrix_count, precond_count);
    return 1;
  }

  if (data->precond == 'Y')
    data->pfiles = find_files(data->pname, &precond_count);
  else if (data->precond == 'N')
    data->pfiles = NULL;
  else
    printf("Bad Precond Input!\n");

  ThreadArgs args1 = {data, CPU_EXECUTION};
  ThreadArgs args2 = {data, GPU_EXECUTION};

  if (data->concurrent == 'Y') {
    printf("\n\tlaunching CCG thread...");
    pthread_create(&th1, NULL, batch_CG, &args1);
    printf("\n\tlaunching GPU CG thread...\n");
    pthread_create(&th2, NULL, batch_CG, &args2);
  } else if (data->concurrent == 'N') {
    printf("\n\trunning GPU CG function...");
    batch_CG(&args2);
    printf("\n\trunning CCG function...");
    batch_CG(&args1);
  } else {
    printf("Bad Concurrency Input!\n");
  }

  if (data->concurrent == 'Y') {
    pthread_join(th1, NULL);
    pthread_join(th2, NULL);
  }

  // Clean
  printf("cleaning memory\n");
  for (i = 0; i < matrix_count; i++) {
    free(data->files[i]);
    if (data->precond == 'Y')
      free(data->pfiles[i]);
  }
  free(data->files);
  free(data->pfiles);
  free(data);
  printf("Tests Complete!\n");

  return 0;
}