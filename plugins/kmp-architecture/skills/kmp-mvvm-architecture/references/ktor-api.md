# Ktor API 層架構（KMP 共享網路層）

## 目的與原則

- **所有網路程式碼放在 commonMain**：Repository、ApiService、Model 完全共享，僅 HttpClient engine 依平台切換（Android 用 OkHttp、iOS 用 Darwin）。
- **不丟例外的呼叫層**：`ApiService` 內部 `try/catch` 吞掉所有例外（網路錯誤、序列化錯誤），一律轉成 `ApiResult.Error` 回傳；Repository 再用 `toResult()` 轉成 Kotlin 標準 `Result<T>`。上層（UseCase / ViewModel）只需處理 `Result`，永遠不需要自己 try/catch 網路呼叫。
- **兩段式成功判斷**：HTTP 層成功（2xx）不代表業務成功，還要看回應 JSON 的 `success` 欄位。`toResult()` 預設會檢查 `success` flag，失敗時取 `message` 作為錯誤訊息。
- **端點集中管理**：所有 API 路徑定義在 `ApiEndpoint` sealed class，並在此宣告該端點是否需要 Bearer token（`requiresAuth`）。
- **token / baseUrl 注入在 ApiService 一處完成**：Repository 不碰 token 與 server URL。

## 架構圖

    ViewModel / UseCase
        │  只看 Result<T> / Result<ApiResponse<T>>
        ▼
    Repository（interface 在 commonMain，Impl 呼叫 ApiService）
        │  apiService.postTyped(...).toResult("錯誤訊息")
        ▼
    ApiService（commonMain，統一呼叫層）
        ├─ prepareRequest()：組 baseUrl + path、注入 Bearer token
        ├─ handleResponse()：2xx → 反序列化；非 2xx → 解析錯誤 message
        └─ try/catch → 全部轉 ApiResult.Success / ApiResult.Error
        │
        ▼
    HttpClient（expect fun createHttpClient(json)）
        ├─ androidMain actual → HttpClient(OkHttp) { ... }
        └─ iosMain actual     → HttpClient(Darwin) { ... }

## 各元件範本

以下範本 package 統一用 `com.example.app.api`，業務端點/欄位以 Sample 佔位。
`ApiService` / `HttpClientFactory` 屬基礎設施，骨架可直接照抄。

### 1. HttpClient 建立（expect/actual）

commonMain 只宣告工廠函式，`Json` 由 DI 傳入：

```kotlin
// commonMain/api/core/HttpClientFactory.kt
package com.example.app.api

import io.ktor.client.HttpClient
import kotlinx.serialization.json.Json

expect fun createHttpClient(json: Json): HttpClient
```

androidMain / iosMain 的 actual **除了 engine 那一行以外完全相同**（共用設定：ContentNegotiation + Json、三種 timeout、Napier logging、預設 Content-Type 與語系 header）：

```kotlin
// androidMain/api/core/HttpClientFactory.kt（iosMain 僅把 OkHttp 換成 Darwin）
package com.example.app.api

import io.github.aakira.napier.Napier
import io.ktor.client.HttpClient
import io.ktor.client.engine.okhttp.OkHttp   // iOS: io.ktor.client.engine.darwin.Darwin
import io.ktor.client.plugins.HttpTimeout
import io.ktor.client.plugins.contentnegotiation.ContentNegotiation
import io.ktor.client.plugins.defaultRequest
import io.ktor.client.plugins.logging.LogLevel
import io.ktor.client.plugins.logging.Logging
import io.ktor.http.ContentType
import io.ktor.http.HttpHeaders
import io.ktor.http.contentType
import io.ktor.serialization.kotlinx.json.json
import kotlinx.serialization.json.Json

private const val DEFAULT_TIMEOUT = 30_000L
private const val DEFAULT_LANGUAGE = "zh-tw"

actual fun createHttpClient(json: Json): HttpClient = HttpClient(OkHttp) {  // iOS: HttpClient(Darwin)
    install(ContentNegotiation) { json(json) }
    install(HttpTimeout) {
        requestTimeoutMillis = DEFAULT_TIMEOUT
        connectTimeoutMillis = DEFAULT_TIMEOUT
        socketTimeoutMillis = DEFAULT_TIMEOUT
    }
    install(Logging) {
        level = LogLevel.BODY
        logger = object : io.ktor.client.plugins.logging.Logger {
            override fun log(message: String) = Napier.d(message, tag = "KtorHttp")
        }
    }
    defaultRequest {
        contentType(ContentType.Application.Json)
        headers.append(HttpHeaders.AcceptLanguage, DEFAULT_LANGUAGE)
    }
}
```

DI 註冊（Koin，`Json` 設定務必開 `ignoreUnknownKeys`）：

```kotlin
val sharedModule = module {
    single {
        Json {
            ignoreUnknownKeys = true
            isLenient = true
            encodeDefaults = true
            prettyPrint = false
            coerceInputValues = true
        }
    }
    single { createHttpClient(get()) }
    single { ApiService(get(), get(), get(), get()) }  // client, json, apiConfig, tokenManager
    single<SampleRepository> { SampleRepositoryImpl(get()) }
}
```

### 2. ApiEndpoints：端點集中管理

```kotlin
// commonMain/api/core/ApiEndpoints.kt
package com.example.app.api

sealed class ApiEndpoint(val path: String, val requiresAuth: Boolean = true) {
    // 不需 token 的端點需明確標示
    data object Authorize : ApiEndpoint("api/authorize/code", requiresAuth = false)

    // 一般業務端點（預設 requiresAuth = true）
    data object SampleList : ApiEndpoint("api/sample/list")
    data object SampleCreate : ApiEndpoint("api/sample/create")

    // 動態路徑逃生口
    class Custom(path: String, requiresAuth: Boolean = true) : ApiEndpoint(path, requiresAuth)
}
```

### 3. ApiResponse<T> 與 ApiResult<T>：統一回應包裝

伺服器回應固定為 `{ success, code, message, data }` 信封；`ApiResult` 則是「HTTP 呼叫層」的成功/失敗（與業務 success 是兩回事）：

```kotlin
// commonMain/api/core/ApiResponse.kt
package com.example.app.api

@Serializable
data class ApiResponse<T>(
    @SerialName("success") val success: Boolean = false,
    @SerialName("code") val code: String = "",
    @SerialName("message") val message: String = "",
    @SerialName("data") val data: T? = null
)

// data 型別未定時用 JsonElement 承接
@Serializable
data class RawApiResponse(
    @SerialName("success") val success: Boolean = false,
    @SerialName("code") val code: String = "",
    @SerialName("message") val message: String = "",
    @SerialName("data") val data: JsonElement? = null
)

sealed class ApiResult<T> {
    data class Success<T>(val data: T) : ApiResult<T>()
    data class Error<T>(
        val code: String = "",
        val message: String = "",
        val data: T? = null,
        val exception: Throwable? = null
    ) : ApiResult<T>()

    val isSuccess: Boolean get() = this is Success
    fun getOrNull(): T? = (this as? Success)?.data
    inline fun <R> fold(onSuccess: (T) -> R, onError: (Error<T>) -> R): R =
        when (this) { is Success -> onSuccess(data); is Error -> onError(this) }
}

/**
 * 銜接點：ApiResult<ApiResponse<T>> → Kotlin 標準 Result<ApiResponse<T>>。
 * checkSuccessFlag = true（預設）時，HTTP 成功但 success=false 也視為失敗，
 * 以回應的 message 建立 Exception；訊息為空則用 errorMessage 預設值。
 */
fun <T> ApiResult<ApiResponse<T>>.toResult(
    errorMessage: String = "Request failed",
    checkSuccessFlag: Boolean = true
): Result<ApiResponse<T>> = when (this) {
    is ApiResult.Success -> {
        val ok = if (checkSuccessFlag) data.success else true
        if (ok) Result.success(data)
        else Result.failure(Exception(data.message.ifEmpty { errorMessage }))
    }
    is ApiResult.Error -> Result.failure(exception ?: Exception(message.ifEmpty { errorMessage }))
}
```

### 4. ApiService：統一呼叫層（骨架可照抄）

重點：**它從不對外丟例外**。所有例外在 `executeRequest` / `postJson` 的 catch 中記錄（Napier + Crashlytics）後轉為 `ApiResult.Error(exception = e)`。

```kotlin
// commonMain/api/core/ApiService.kt
package com.example.app.api

class ApiService(
    @PublishedApi internal val httpClient: HttpClient,
    @PublishedApi internal val json: Json,
    @PublishedApi internal val apiConfig: IApiConfig,      // 提供 baseUrl
    @PublishedApi internal val tokenManager: ITokenManager // 提供 access token
) {
    // ── 底層：泛型請求 + 錯誤轉換 ──
    private suspend fun <T> executeRequest(
        endpoint: ApiEndpoint,
        params: Map<String, String>,
        deserializer: (String) -> T,
        requestBuilder: suspend (String, Parameters, Map<String, String>) -> HttpResponse
    ): ApiResult<T> = try {
        val (url, headers) = prepareRequest(endpoint)
            ?: return ApiResult.Error(message = "Request preparation failed")
        val parameters = Parameters.build { params.forEach { (k, v) -> append(k, v) } }
        handleResponse(requestBuilder(url, parameters, headers), deserializer, endpoint.path)
    } catch (e: Exception) {
        Napier.e(e.message ?: "Unknown error", e, tag = "ApiService")
        ApiResult.Error(message = e.message ?: "Unknown error", exception = e)
    }

    // token / baseUrl 注入：baseUrl 未設定或需要 token 但拿不到 → 回 null（上層轉 Error）
    @PublishedApi
    internal suspend fun prepareRequest(endpoint: ApiEndpoint): Pair<String, Map<String, String>>? {
        val baseUrl = apiConfig.getServerUrl()
        if (baseUrl.isNullOrEmpty()) return null
        val headers = mutableMapOf<String, String>()
        if (endpoint.requiresAuth) {
            val token = tokenManager.getAccessToken()
            if (token.isNullOrEmpty()) return null
            headers[HttpHeaders.Authorization] = "Bearer $token"
        }
        return "$baseUrl${endpoint.path}" to headers
    }

    // 非 2xx：嘗試解析錯誤信封取 message，失敗則回 "HTTP {code}: {description}"
    @PublishedApi
    internal suspend fun <T> handleResponse(
        response: HttpResponse,
        deserializer: (String) -> T,
        endpointPath: String = ""
    ): ApiResult<T> {
        return if (response.status.isSuccess()) {
            ApiResult.Success(deserializer(response.bodyAsText()))
        } else {
            val body = response.bodyAsText()
            val errorMsg = try {
                json.decodeFromString<RawApiResponse>(body).message
            } catch (e: Exception) {
                "HTTP ${response.status.value}: ${response.status.description}"
            }
            ApiResult.Error(code = response.status.value.toString(), message = errorMsg)
        }
    }

    // ── 對外 API（依 body 形式挑一種）──

    // (a) JSON body：request 物件直接序列化為 JSON
    suspend inline fun <reified Req : ApiRequest, reified Res> postTyped(
        endpoint: ApiEndpoint, request: Req
    ): ApiResult<ApiResponse<Res>> = postJson<Res>(endpoint, json.encodeToString(request))

    // (b) 包一層 { "data": "<json string>" } 的舊式後端格式
    suspend inline fun <reified Req : ApiRequest, reified Res> postTypedWrapData(
        endpoint: ApiEndpoint, request: Req
    ): ApiResult<ApiResponse<Res>> =
        postJson<Res>(endpoint, json.encodeToString(PostRequestDataParam(json.encodeToString(request))))

    // (c) GET：request 物件經 FormParameterEncoder 轉為 query string
    suspend inline fun <reified Req : ApiRequest, reified Res> getTyped(
        endpoint: ApiEndpoint, request: Req
    ): ApiResult<ApiResponse<Res>> = getTyped<Res>(endpoint, request.toFormParameters())

    // (d) 回應不是標準信封時，直接反序列化為自訂型別
    suspend inline fun <reified T> getCustomTyped(
        endpoint: ApiEndpoint, params: Map<String, String> = emptyMap()
    ): ApiResult<T> = get(endpoint, params) { body -> json.decodeFromString<T>(body) }

    // 另有 post()/get()（form/query + 自訂 deserializer）、postRaw()/getRaw()（RawApiResponse）、
    // postJson()（JSON 字串 body），骨架見命名與位置範例（相對結構）。
}
```

### 5. ApiRequest 與自訂 serializer

```kotlin
// 標記介面：所有 request data class 都要實作，才能用 postTyped/getTyped 泛型方法
interface ApiRequest

@Serializable
data class SampleListRequest(
    @SerialName("page") val page: Int,
    @SerialName("keyword") val keyword: String = ""
) : ApiRequest
```

**RequestSerializer.kt 提供兩個工具，時機如下：**

1. `JsonStringSerializer<T>`：當後端要求「巢狀物件以 JSON *字串* 傳遞」時，掛在欄位上把物件序列化成字串值：

```kotlin
object SampleDetailAsStringSerializer : JsonStringSerializer<SampleDetail>(SampleDetail.serializer())

@Serializable
data class SampleRequest(
    @Serializable(with = SampleDetailAsStringSerializer::class)
    @SerialName("detail") val detail: SampleDetail  // 送出時變成 "{\"a\":1}"
) : ApiRequest
```

2. `FormParameterEncoder` + `toFormParameters()`：把 `@Serializable` 物件攤平成 `Map<String, String>`，供 GET query string 或 form-urlencoded body 使用（`getTyped(endpoint, request)` 內部就是走這條路；null 欄位會被略過）。

**EmptyStringAsNullSerializer**：後端習慣用 `""` 代替 `null` 回傳物件/數字欄位時，直接 decode 會炸序列化錯誤。掛上此 serializer 後，值為空字串 → 反序列化為 `null`，否則走原 serializer：

```kotlin
object SampleInfoOrNullSerializer : EmptyStringAsNullSerializer<SampleInfo>(SampleInfo.serializer())

@Serializable
data class SampleResponse(
    @Serializable(with = SampleInfoOrNullSerializer::class)
    @SerialName("info") val info: SampleInfo?   // 後端回 "" 時得到 null
)
```

### 6. Repository 標準寫法範本

Repository interface 定義在 commonMain，回傳型別一律是 `Result<...>`；Impl 只做「挑 ApiService 方法 + toResult 轉換」：

```kotlin
class SampleRepositoryImpl(
    private val apiService: ApiService,
) : SampleRepository {

    // 標準款：JSON body + 標準信封 + 檢查 success flag
    override suspend fun getSampleList(page: Int): Result<ApiResponse<List<SampleItem>>> {
        val request = SampleListRequest(page)
        return apiService.postTyped<SampleListRequest, List<SampleItem>>(
            endpoint = ApiEndpoint.SampleList,
            request = request
        ).toResult(errorMessage = "取得列表失敗")
    }

    // 不檢查 success flag（某些端點 success=false 仍屬正常流程，由上層自行判斷）
    override suspend fun createSample(request: CreateSampleRequest): Result<ApiResponse<SampleData>> {
        return apiService.postTypedWrapData<CreateSampleRequest, SampleData>(
            endpoint = ApiEndpoint.SampleCreate,
            request = request
        ).toResult(errorMessage = "建立失敗", false)
    }

    // 沒有參數時用 EmptyParam 佔位物件
    override suspend fun getInfo(): Result<ApiResponse<SampleInfo>> {
        return apiService.postTyped<EmptyParam, SampleInfo>(
            endpoint = ApiEndpoint.SampleList,
            request = EmptyParam
        ).toResult(errorMessage = "取得資訊失敗")
    }

    // 非標準信封：getCustomTyped + 手動 fold 成 Result
    override suspend fun getQrcode(): Result<QrcodeResponse> {
        return when (val result = apiService.getCustomTyped<QrcodeApiResponse>(ApiEndpoint.Custom("api/qrcode"))) {
            is ApiResult.Success -> {
                val r = result.data
                if (r.success) Result.success(QrcodeResponse(url = r.data ?: ""))
                else Result.failure(Exception(r.message.ifEmpty { "取得 QR Code 失敗" }))
            }
            is ApiResult.Error -> Result.failure(result.exception ?: Exception(result.message))
        }
    }
}
```

## 常見錯誤

1. **在 Repository / ViewModel 再包 try/catch**：`ApiService` 已保證不丟例外，多包只會吞掉錯誤路徑。統一用 `Result` 的 `onFailure/fold` 處理。
2. **忘記 `toResult()` 的雙層語意**：`ApiResult.Success` 只代表 HTTP 2xx 且反序列化成功；業務失敗（`success=false`）要靠 `toResult(checkSuccessFlag = true)` 轉成 `Result.failure`。直接 `getOrNull()` 拿信封而不看 `success` 是常見 bug 來源。
3. **端點路徑寫死在 Repository**：一律新增 `ApiEndpoint` data object；臨時/動態路徑才用 `ApiEndpoint.Custom`。
4. **request data class 忘了實作 `ApiRequest`**：泛型方法有 `Req : ApiRequest` 上界，漏掉會編譯錯誤；這是刻意的防呆。
5. **Json 設定不一致**：`Json` 實例由 DI 單例提供並同時餵給 `HttpClient` 與 `ApiService`，不要在 Repository 內另建 `Json{}`（`JsonStringSerializer` 內部自帶的除外）。
6. **後端 `""` 當 null 造成 decode 崩潰**：對可能回空字串的物件/數值欄位掛 `EmptyStringAsNullSerializer`，並確保 `Json` 開啟 `ignoreUnknownKeys` / `coerceInputValues`。
7. **actual HttpClientFactory 設定漂移**：android/ios 兩份 actual 除 engine 外必須逐行相同；改 timeout、header 等共用設定時兩邊都要改。
8. **GET 帶巢狀物件**：`FormParameterEncoder` 只攤平純量欄位，巢狀物件需先用 `JsonStringSerializer` 轉成字串欄位，否則會遺失資料。

## 命名與位置範例（相對結構）

| 元件 | 路徑 |
|------|------|
| expect createHttpClient | `commonMain: api/core/HttpClientFactory.kt` |
| actual（OkHttp） | `androidMain: api/core/HttpClientFactory.kt` |
| actual（Darwin） | `iosMain: api/core/HttpClientFactory.kt` |
| ApiService | `commonMain: api/core/ApiService.kt` |
| ApiResponse / ApiResult / toResult | `commonMain: api/core/ApiResponse.kt` |
| ApiEndpoint | `commonMain: api/core/ApiEndpoints.kt` |
| ApiRequest 標記介面 | `commonMain: api/core/ApiRequest.kt` |
| JsonStringSerializer / FormParameterEncoder | `commonMain: api/core/RequestSerializer.kt` |
| EmptyStringAsNullSerializer | `commonMain: api/core/EmptyStringAsNullSerializer.kt` |
| Repository 範例 | `commonMain: api/repository/login/LoginRepositoryImpl.kt` |
| DI 註冊（Json / HttpClient / ApiService） | `commonMain: di/AppModule.kt`（`sharedModule`） |
