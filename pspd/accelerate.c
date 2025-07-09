#include <stdio.h>
#include <stdlib.h>
#include <time.h>
#include <Accelerate/Accelerate.h>

#define N 512 // tamanho da matriz NxN

void matrixMultiplyCPU(float* A, float* B, float* C, int n) {
    for (int i = 0; i < n; i++)
        for (int j = 0; j < n; j++) {
            float sum = 0;
            for (int k = 0; k < n; k++)
                sum += A[i*n + k] * B[k*n + j];
            C[i*n + j] = sum;
        }
}

double get_time_ms() {
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return ts.tv_sec * 1000.0 + ts.tv_nsec / 1.0e6;
}

int main() {
    float *A = malloc(sizeof(float) * N * N);
    float *B = malloc(sizeof(float) * N * N);
    float *C_cpu = malloc(sizeof(float) * N * N);
    float *C_accel = malloc(sizeof(float) * N * N);

    // Inicializar com valores aleatórios
    for (int i = 0; i < N*N; i++) {
        A[i] = (float)rand() / RAND_MAX;
        B[i] = (float)rand() / RAND_MAX;
    }

    // CPU pura
    double start = get_time_ms();
    matrixMultiplyCPU(A, B, C_cpu, N);
    double end = get_time_ms();
    printf("⏱ Tempo CPU: %.3f ms\n", end - start);

    // Accelerate (usa GPU integrada / SIMD / otimizações)
    start = get_time_ms();
    cblas_sgemm(CblasRowMajor, CblasNoTrans, CblasNoTrans,
                N, N, N,
                1.0f, A, N,
                      B, N,
                0.0f, C_accel, N);
    end = get_time_ms();
    printf("⚡️ Tempo Accelerate (BLAS): %.3f ms\n", end - start);

    // Limpeza
    free(A); free(B); free(C_cpu); free(C_accel);
    return 0;
}

