#include <stdio.h>
#include <stdlib.h>
#include <time.h>
#include <Accelerate/Accelerate.h>

#define N 512          // Tamanho da matriz NxN
#define REPS 100       // Número de repetições da multiplicação

// Multiplicação de matrizes na CPU (for loops simples)
void matrixMultiplyCPU(float* A, float* B, float* C, int n) {
    for (int i = 0; i < n; i++)
        for (int j = 0; j < n; j++) {
            float sum = 0;
            for (int k = 0; k < n; k++)
                sum += A[i*n + k] * B[k*n + j];
            C[i*n + j] = sum;
        }
}

// Função auxiliar para pegar tempo em milissegundos
double get_time_ms() {
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return ts.tv_sec * 1000.0 + ts.tv_nsec / 1.0e6;
}

int main() {
    // Alocar memória para as matrizes
    float *A = malloc(sizeof(float) * N * N);
    float *B = malloc(sizeof(float) * N * N);
    float *C_cpu = malloc(sizeof(float) * N * N);
    float *C_accel = malloc(sizeof(float) * N * N);

    // Preencher A e B com valores aleatórios
    for (int i = 0; i < N*N; i++) {
        A[i] = (float)rand() / RAND_MAX;
        B[i] = (float)rand() / RAND_MAX;
    }

    // ⏱ Teste da CPU
    double start = get_time_ms();
    for (int r = 0; r < REPS; r++)
        matrixMultiplyCPU(A, B, C_cpu, N);
    double end = get_time_ms();
    printf("⏱ Tempo CPU (%d reps): %.3f ms\n", REPS, end - start);
    printf("Valor de verificação CPU: %f\n", C_cpu[0]);  // Evita otimização

    // ⚡️ Teste com Accelerate (BLAS otimizado)
    start = get_time_ms();
    for (int r = 0; r < REPS; r++)
        cblas_sgemm(CblasRowMajor, CblasNoTrans, CblasNoTrans,
                    N, N, N,
                    1.0f, A, N,
                          B, N,
                    0.0f, C_accel, N);
    end = get_time_ms();
    printf("⚡️ Tempo Accelerate (BLAS, %d reps): %.3f ms\n", REPS, end - start);
    printf("Valor de verificação BLAS: %f\n", C_accel[0]);  // Evita otimização

    // Limpar memória
    free(A); free(B); free(C_cpu); free(C_accel);
    return 0;
}
