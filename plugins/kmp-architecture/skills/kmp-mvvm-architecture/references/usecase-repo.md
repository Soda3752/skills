# UseCase / Repository / StateHolder 分層慣例

本文件記載 本架構 `commonMain` 的資料流分層慣例：UseCase、Repository、StateHolder 與 Model 的放置位置、命名、依賴注入與撰寫骨架。所有骨架均忠於現有原始碼，移植或新增功能時照此套用。

## 目的與原則

- **ViewModel 保持薄**：ViewModel 只負責 UI 狀態組裝與事件轉發，不直接組合多個資料來源。
- **UseCase 承載業務邏輯**：凡是「跨多個 Repository / Storage 的流程編排」「有明確業務語意的判斷（如：unchanged 跳過、best-effort 上傳）」都抽成 UseCase。
- **Repository 只做資料存取**：一個 Repository 方法對應一個 API endpoint（或一個本地存取動作），不含流程編排。介面與實作都放在 `commonMain`（平台差異已由 `ApiService` / 儲存介面吸收）。
- **單純轉發不必抽 UseCase**：若 ViewModel 只是呼叫單一 Repository 方法、拿到結果直接映射成 UI 狀態，可直接注入 Repository，不需要為了「有一層」而多包一層。
- **跨畫面共享狀態用 StateHolder**：不落 DB、不走 API 的全局執行期狀態（GPS 位置、距離單位、語系）以 Holder 類別集中，Koin `single` 註冊，多個 ViewModel 共用。

## 分層圖

```
ViewModel（screen/<feature>/）
   │  只注入 UseCase 或（單純情境）Repository
   ▼
UseCase（screen/<feature>/domain/）
   │  組合多個 Repository / LocalStorage 介面 / 其他 UseCase / StateHolder
   ├──────────────► StateHolder（全局狀態中介層，Koin single）
   ▼
Repository interface + Impl（api/repository/<domain>/）
   │  一方法一 endpoint，回傳 Result<ApiResponse<Model>>
   ├──────────────► LocalStorage 介面（localstorage/，如 ICoreDataStorage）
   ▼
ApiService（api/core/，Ktor 封裝，postTyped / toResult）
   ▼
Model（model/<domain>/，@Serializable data class）
```

依賴方向永遠往下；下層不得 import 上層（Repository 不認識 UseCase，UseCase 不認識 ViewModel）。

## UseCase 慣例

- **位置**：`screen/<feature>/domain/`，跟著使用它的畫面走（例：`screen/login/domain/`、`screen/main/score/domain/`）。多畫面共用的 UseCase 也照此放，由 Koin `single` 共享。
- **命名**：`動詞 + 名詞 + UseCase`（FetchAllInfoUseCase、VerifyDevModeCodeUseCase、LogoutUseCase、DeleteScoreCardUseCase）。
- **建構子注入**：Repository、LocalStorage 介面（`ICoreDataStorage` 等）、其他 UseCase、StateHolder，全部走建構子，無 field injection。
- **呼叫慣例（實況）**：主流是 `suspend operator fun invoke(...)`；少數較早期的 UseCase（如 `DownloadResourcesUseCase`）用具名的 `execute(...)`。**新寫一律用 `suspend operator fun invoke`**。
- **回傳型別（實況，兩種並存）**：
  1. 結果分支有業務語意時，定義**巢狀 `sealed class Result`**（如 `Success / NetworkError / WrongPassword`），呼叫端 `when` 窮舉。
  2. 只有成功／失敗兩態時，直接回傳 `kotlin.Result<T>`（如 `LogoutUseCase` 回 `Result<Unit>`）。
- **私有輔助函式**：流程中的子步驟拆成 `private suspend fun`（如 `uploadScore`、`downloadIfNeeded`），保持 `invoke` 是可讀的流程主幹。
- **執行緒**：重 IO 的本地寫入以 `withContext(Dispatchers.IO)` 包裹；網路呼叫本身已在 ApiService 層處理，UseCase 不需再切 dispatcher。
- **日誌**：用 `util/Logger`（Napier 封裝），格式 `Logger.d("類名縮寫: 訊息")`。
- **Koin 註冊**：在 `di/AppModule.kt` 的 `sharedModule` 以 `single { XxxUseCase(get(), ...) }` 註冊（本架構 UseCase 一律 `single`，非 `factory`）。

## UseCase 範本

### 簡單型（單一 Repository、sealed Result）

```kotlin
package com.example.app.screen.sample.domain

import com.example.app.api.repository.sample.SampleRepository
import com.example.app.model.sample.VerifySampleRequest
import com.example.app.util.isNetworkError

class VerifySampleCodeUseCase(
    private val sampleRepository: SampleRepository,
) {
    sealed class Result {
        data object Success : Result()
        data object NetworkError : Result()
        data object WrongCode : Result()
    }

    suspend operator fun invoke(inputCode: String): Result {
        val result = sampleRepository.verifyCode(VerifySampleRequest(code = inputCode))
        return result.fold(
            onSuccess = { Result.Success },
            onFailure = { error ->
                if (error.isNetworkError()) Result.NetworkError else Result.WrongCode
            }
        )
    }
}
```

### 組合型（多 Repository / Storage / 子 UseCase 編排）

```kotlin
package com.example.app.screen.sample.domain

import com.example.app.api.repository.sample.SampleRepository
import com.example.app.localstorage.ISampleStorage
import com.example.app.util.Logger
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.IO
import kotlinx.coroutines.withContext

/**
 * 拉取並同步 Sample 資料的 UseCase
 *
 * - 若伺服器回應 unchanged → 跳過更新，視為成功
 * - 若有新資料 → 儲存至本地快取，並觸發後續（best-effort）動作
 */
class FetchSampleUseCase(
    private val sampleRepository: SampleRepository,
    private val sampleStorage: ISampleStorage,
    private val downloadSampleUseCase: DownloadSampleUseCase, // 可組合其他 UseCase
) {
    sealed class Result {
        data object Success : Result()
        data class Failure(val message: String?) : Result()
    }

    suspend operator fun invoke(): Result {
        val apiResult = sampleRepository.getSampleInfo(isForce = true)
        if (apiResult.exceptionOrNull()?.message == "unchanged") {
            Logger.d("FetchSample: 伺服器回應 unchanged，跳過更新")
            return Result.Success
        }

        return apiResult.fold(
            onSuccess = { response ->
                withContext(Dispatchers.IO) {
                    response.data?.let { sampleStorage.saveSampleInfo(it) }
                }
                downloadIfNeeded()
                Result.Success
            },
            onFailure = { exception ->
                Logger.e("FetchSample: 拉取失敗", exception)
                Result.Failure(exception.message)
            }
        )
    }

    // 子步驟拆 private suspend fun，best-effort 失敗不阻斷主流程
    private suspend fun downloadIfNeeded() {
        downloadSampleUseCase()
            .onFailure { Logger.e("FetchSample: 背景下載失敗，忽略繼續", it) }
    }
}
```

## Repository 慣例

- **位置**：`api/repository/<domain>/`，每個領域一個資料夾，內含 `XxxRepository.kt`（interface）+ `XxxRepositoryImpl.kt` 成對。現有領域：`cart`、`download`、`event`、`game`、`install`、`iothub`、`location`、`login`、`restaurant`、`upload`。
- **介面方法**：全部 `suspend fun`，回傳 `Result<ApiResponse<Model>>`（少數自訂回應如 `Result<QrcodeResponse>` 或 `Result<Unit>`）。Model 型別來自 `model/<domain>/`。
- **Impl 依賴**：主要注入 `ApiService`；需要本地資料的領域再注入儲存介面（如 `InstallRepositoryImpl` 多注入兩個依賴）。
- **一方法一 endpoint**：方法體固定三段——組 request → `apiService.postTyped<Req, Resp>(endpoint, request)` → `.toResult(errorMessage = "…失敗")`。錯誤訊息為繁體中文業務描述。
- **Koin 註冊**：`single<XxxRepository> { XxxRepositoryImpl(get()) }`，介面型別對外、Impl 只在 DI 中出現。

## Repository 範本

```kotlin
// api/repository/sample/SampleRepository.kt
package com.example.app.api.repository.sample

import com.example.app.api.core.ApiResponse
import com.example.app.model.sample.SampleInfoResponse
import com.example.app.model.sample.VerifySampleRequest

interface SampleRepository {

    suspend fun getSampleInfo(isForce: Boolean): Result<ApiResponse<SampleInfoResponse>>

    suspend fun verifyCode(request: VerifySampleRequest): Result<Unit>
}
```

```kotlin
// api/repository/sample/SampleRepositoryImpl.kt
package com.example.app.api.repository.sample

import com.example.app.api.core.ApiEndpoint
import com.example.app.api.core.ApiResponse
import com.example.app.api.core.ApiService
import com.example.app.api.core.toResult
import com.example.app.model.EmptyParam
import com.example.app.model.sample.SampleInfoRequest
import com.example.app.model.sample.SampleInfoResponse
import com.example.app.model.sample.VerifySampleRequest

class SampleRepositoryImpl(
    private val apiService: ApiService,
) : SampleRepository {

    override suspend fun getSampleInfo(isForce: Boolean): Result<ApiResponse<SampleInfoResponse>> {
        val request = SampleInfoRequest(isForce)
        return apiService.postTyped<SampleInfoRequest, SampleInfoResponse>(
            endpoint = ApiEndpoint.SampleInfo,
            request = request
        ).toResult(errorMessage = "取得 Sample 資訊失敗")
    }

    override suspend fun verifyCode(request: VerifySampleRequest): Result<Unit> {
        return apiService.postTyped<VerifySampleRequest, EmptyParam>(
            endpoint = ApiEndpoint.VerifySampleCode,
            request = request
        ).toResult(errorMessage = "驗證失敗").map { }
    }
}
```

## StateHolder 模式（全局狀態中介層）

不走 API、不落地持久化，但需要**跨多個 ViewModel 共享**的執行期狀態，用純 class + Flow 的 Holder，Koin `single` 註冊。現有實例：

- `LocationStateHolder`（`api/repository/location/`）：`MutableSharedFlow<LocationData>(replay = 1)`。由 MainScreenViewModel 收集 GPS 後 `emit`，FairWayViewModel 等訂閱，確保全局只有一個 GPS Listener；`reset()` 以 `resetReplayCache()` 清掉舊來源殘留位置。
- `DistanceUnitHolder`（`screen/main/fairway/domain/`）：`MutableStateFlow<DistanceUnit>`，距離單位的單一真實來源，畫面顯示與語音播報共讀，重啟回預設值。
- 同慣例還有 `LanguageStateHolder`、`FairwayTrackResultHolder`、`UploadLocationStateHolder`。

骨架：

```kotlin
class SampleStateHolder {

    private val _state = MutableStateFlow(SampleState.DEFAULT)
    val state: StateFlow<SampleState> = _state.asStateFlow()

    fun update(value: SampleState) {
        _state.value = value
    }
}
// Koin: single { SampleStateHolder() }
```

選型：需要「延遲訂閱者拿到最新一筆事件」用 `MutableSharedFlow(replay = 1)`；單純「目前值」用 `MutableStateFlow`。

## Model 慣例

- 放 `model/<domain>/`（login、game、score、upload、download、install、cart、event、iothub、restaurant、device），子領域可再開資料夾（如 `model/login/card/`、`model/login/coredata/`）。
- 一律 `@Serializable data class`，欄位用 `@SerialName("ServerFieldName")` 對應伺服器命名（伺服器多為 PascalCase）。
- Request 類實作 `ApiRequest` 標記介面；無參數請求用共用的 `model/EmptyParam.kt`。
- 禁止出現任何 Android / iOS 平台型別。

```kotlin
@Serializable
data class AddSampleRequest(
    @SerialName("SampleName")
    val sampleName: String,
    @SerialName("SampleCount")
    val sampleCount: Int,
) : ApiRequest
```

## 常見錯誤

1. **在 ViewModel 直接編排多 Repository 流程** — 上傳成績→上傳評鑑→登出這種多步流程必須抽 UseCase（見 `LogoutUseCase`），否則邏輯無法被其他入口（FCM、背景同步）重用。
2. **UseCase 用 `execute` 命名新方法** — 新程式碼一律 `suspend operator fun invoke`；`execute` 只是少數既有 UseCase 的歷史寫法，不要模仿擴散。
3. **Repository 回傳原始 `ApiResult` 或丟例外給上層** — 一律在 Impl 內 `.toResult(errorMessage = ...)` 收斂成 `Result`，錯誤訊息在 Repository 層就給好繁中文案。
4. **忘記 Koin 註冊或型別綁到 Impl** — Repository 必須 `single<介面> { Impl(get()) }`；UseCase / StateHolder 直接 `single { ... }`。漏註冊會在執行期才炸 `NoDefinitionFoundException`。
5. **把跨 ViewModel 狀態塞進某個 ViewModel 再互相引用** — 用 StateHolder；ViewModel 之間不得互相依賴。
6. **Model 混入平台型別或省略 `@SerialName`** — 伺服器欄位是 PascalCase，漏標會序列化錯欄位名而且編譯不會報錯。
7. **best-effort 步驟失敗阻斷主流程** — 非關鍵子步驟（評鑑上傳、背景下載）用 `runCatching { ... }` 或 `.onFailure { log }` 吞掉，主流程照走。

## 命名與位置範例（相對結構）

以下皆相對於 `commonMain: `：

| 角色 | 檔案 |
|------|------|
| 簡單 UseCase | `screen/login/domain/VerifyDevModeCodeUseCase.kt`（單一 Repo + sealed Result） |
| 組合 UseCase | `screen/login/domain/FetchAllInfoUseCase.kt`（Repo + Storage + FileManager + 子 UseCase） |
| 多 Repo 流程 UseCase | `screen/main/score/domain/LogoutUseCase.kt`（上傳→評鑑→登出，回 `Result<Unit>`） |
| Repository 介面 | `api/repository/login/LoginRepository.kt` |
| Repository 實作 | `api/repository/login/LoginRepositoryImpl.kt` |
| 其他領域資料夾 | `api/repository/{cart,download,event,game,install,iothub,location,restaurant,upload}/` |
| StateHolder | `api/repository/location/LocationStateHolder.kt`、`screen/main/fairway/domain/DistanceUnitHolder.kt` |
| Model 範例 | `model/login/AddGameRequest.kt` |
| Koin 註冊 | `di/AppModule.kt`（`sharedModule`：Repositories / UseCases / StateHolders / viewModel） |
