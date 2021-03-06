/*
 * Copyright (c) 2018, NVIDIA CORPORATION.
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

#include <gtest/gtest.h>
#include "stats/mean.h"
#include "random/rng.h"
#include "test_utils.h"
#include "cuda_utils.h"
#include <stdio.h>
#include <stdlib.h>

namespace MLCommon {
namespace Stats {

template<typename T>
struct MeanInputs {
	T tolerance, mean;
	int rows, cols;
	bool sample, rowMajor;
	unsigned long long int seed;
};

template<typename T>
::std::ostream& operator<<(::std::ostream& os, const MeanInputs<T>& dims) {
	return os;
}

template<typename T>
class MeanTest: public ::testing::TestWithParam<MeanInputs<T> > {
protected:
	void SetUp() override {
		params = ::testing::TestWithParam<MeanInputs<T>>::GetParam();
		Random::Rng<T> r(params.seed);

		int rows = params.rows, cols = params.cols;
		int len = rows * cols;
		allocate(data, len);
		allocate(mean_act, cols);
		r.normal(data, len, params.mean, (T) 1.0);

		meanSGtest(data);

		CUDA_CHECK(cudaGetDeviceCount(&device_count));

		if (device_count > 1) {
			T *h_data = (T *) malloc(len * sizeof(T));
			updateHost(h_data, data, len);
			meanMGColSplitTest(h_data);
			free(h_data);
		}

	}

	void meanSGtest(T *data) {
		int rows = params.rows, cols = params.cols;

		cudaStream_t stream;
		CUDA_CHECK(cudaStreamCreate(&stream));
		mean(mean_act, data, cols, rows, params.sample, params.rowMajor,
				stream);
	}

	void meanMGColSplitTest(T *h_data) {
		int n_gpus = 2;

		TypeMG<T> d_data[n_gpus];
		TypeMG<T> d_mu[n_gpus];

		for (int i = 0; i < n_gpus; i++) {
			d_data[i].gpu_id = i;
			d_mu[i].gpu_id = i;
			CUDA_CHECK(cudaSetDevice(d_data[i].gpu_id));
			CUDA_CHECK(cudaStreamCreate(&(d_data[i].stream)));
			d_mu[i].stream = d_data[i].stream;
		}

		allocateMG(d_data, n_gpus, params.rows, params.cols, true, true, false);
		allocateMG(d_mu, n_gpus, 1, params.cols, true, true, false);

		updateDeviceMG(d_data, h_data, n_gpus, false);

		meanMG(d_mu, d_data, params.cols, params.rows, n_gpus, true, false,
				false, false);

		int len = params.cols;
		T *h_mu = (T *) malloc(len * sizeof(T));
		updateHostMG(h_mu, d_mu, n_gpus, false);

		streamSyncMG(d_data, n_gpus);
		streamDestroyGPUs(d_data, n_gpus);

		freeMG(d_data, n_gpus);
		freeMG(d_mu, n_gpus);

		allocate(mean_act_2, len);
		updateDevice(mean_act_2, h_mu, len);

		free(h_mu);
	}

	void meanMGRowSplitTest(T *h_data) {
		int n_gpus = 2;

		TypeMG<T> d_data[n_gpus];
		TypeMG<T> d_mu[n_gpus];

		for (int i = 0; i < n_gpus; i++) {
			d_data[i].gpu_id = i;
			d_mu[i].gpu_id = i;
			CUDA_CHECK(cudaSetDevice(d_data[i].gpu_id));
			CUDA_CHECK(cudaStreamCreate(&(d_data[i].stream)));
			d_mu[i].stream = d_data[i].stream;
		}

		allocateMG(d_data, n_gpus, params.rows, params.cols, true, true, true);
		allocateMG(d_mu, n_gpus, 1, params.cols, true, true, false);

		updateDeviceMG(d_data, h_data, n_gpus, false);

		meanMG(d_mu, d_data, params.cols, params.rows, n_gpus, true, false,
				true, false);

		int len = params.cols;
		T *h_mu = (T *) malloc(len * sizeof(T));
		updateHostMG(h_mu, d_mu, n_gpus, false);

		streamSyncMG(d_data, n_gpus);
		streamDestroyGPUs(d_data, n_gpus);

		freeMG(d_data, n_gpus);
		freeMG(d_mu, n_gpus);

		allocate(mean_act_3, len);
		updateDevice(mean_act_3, h_mu, len);

		free(h_mu);
	}

	void TearDown() override {
		CUDA_CHECK(cudaFree(data));
		CUDA_CHECK(cudaFree(mean_act));
		if (device_count > 1) {
			CUDA_CHECK(cudaFree(mean_act_2));
			//CUDA_CHECK(cudaFree(mean_act_3));
		}
	}

protected:
	MeanInputs<T> params;
	T *data, *mean_act, *mean_act_2, *mean_act_3;
	int device_count = 0;
};

const std::vector<MeanInputs<float> > inputsf = { { 0.05f, 1.f, 1024, 32, true,
		false, 1234ULL }, { 0.05f, 1.f, 1024, 64, true, false, 1234ULL }, {
		0.05f, 1.f, 1024, 128, true, false, 1234ULL }, { 0.05f, 1.f, 1024, 256,
		true, false, 1234ULL },
		{ 0.05f, -1.f, 1024, 32, false, false, 1234ULL }, { 0.05f, -1.f, 1024,
				64, false, false, 1234ULL }, { 0.05f, -1.f, 1024, 128, false,
				false, 1234ULL }, { 0.05f, -1.f, 1024, 256, false, false,
				1234ULL }, { 0.05f, 1.f, 1024, 32, true, true, 1234ULL }, {
				0.05f, 1.f, 1024, 64, true, true, 1234ULL }, { 0.05f, 1.f, 1024,
				128, true, true, 1234ULL }, { 0.05f, 1.f, 1024, 256, true, true,
				1234ULL }, { 0.05f, -1.f, 1024, 32, false, true, 1234ULL }, {
				0.05f, -1.f, 1024, 64, false, true, 1234ULL }, { 0.05f, -1.f,
				1024, 128, false, true, 1234ULL }, { 0.05f, -1.f, 1024, 256,
				false, true, 1234ULL } };

const std::vector<MeanInputs<double> > inputsd = { { 0.05, 1.0, 1024, 32, true,
		false, 1234ULL }, { 0.05, 1.0, 1024, 64, true, false, 1234ULL }, { 0.05,
		1.0, 1024, 128, true, false, 1234ULL }, { 0.05, 1.0, 1024, 256, true,
		false, 1234ULL }, { 0.05, -1.0, 1024, 32, false, false, 1234ULL }, {
		0.05, -1.0, 1024, 64, false, false, 1234ULL }, { 0.05, -1.0, 1024, 128,
		false, false, 1234ULL },
		{ 0.05, -1.0, 1024, 256, false, false, 1234ULL }, { 0.05, 1.0, 1024, 32,
				true, true, 1234ULL }, { 0.05, 1.0, 1024, 64, true, true,
				1234ULL }, { 0.05, 1.0, 1024, 128, true, true, 1234ULL }, {
				0.05, 1.0, 1024, 256, true, true, 1234ULL }, { 0.05, -1.0, 1024,
				32, false, true, 1234ULL }, { 0.05, -1.0, 1024, 64, false, true,
				1234ULL }, { 0.05, -1.0, 1024, 128, false, true, 1234ULL }, {
				0.05, -1.0, 1024, 256, false, true, 1234ULL } };

typedef MeanTest<float> MeanTestF;
TEST_P(MeanTestF, Result) {
	ASSERT_TRUE(
			devArrMatch(params.mean, mean_act, params.cols,
					CompareApprox<float>(params.tolerance)));

	if (device_count > 1) {
		ASSERT_TRUE(
				devArrMatch(params.mean, mean_act_2, params.cols,
						CompareApprox<float>(params.tolerance)));

	}
}

typedef MeanTest<double> MeanTestD;
TEST_P(MeanTestD, Result) {
	ASSERT_TRUE(
			devArrMatch(params.mean, mean_act, params.cols,
					CompareApprox<double>(params.tolerance)));

	if (device_count > 1) {
		ASSERT_TRUE(
				devArrMatch(params.mean, mean_act_2, params.cols,
						CompareApprox<double>(params.tolerance)));

	}
}

INSTANTIATE_TEST_CASE_P(MeanTests, MeanTestF, ::testing::ValuesIn(inputsf));

INSTANTIATE_TEST_CASE_P(MeanTests, MeanTestD, ::testing::ValuesIn(inputsd));

} // end namespace Stats
} // end namespace MLCommon
