# Nova/Filament 최종 마이그레이션 구현 계획

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** sv-nova-master의 잔여 기능 5건을 SVGW로 이관하여 Nova/Filament 완전 제거 준비

**Architecture:** 기존 SVGW의 패턴(Controller + Vue 3 SPA + Sanctum 인증)을 따라 5개 Sprint를 순차 구현한다. DriverConfig 편집 폼 확장(Sprint 1-2), 알림 설정 CRUD(Sprint 3), MongoDB 리뷰 조회(Sprint 4), 리포트 워크플로우(Sprint 5)로 진행한다.

**Tech Stack:** Laravel 12, PHP 8.4, Vue 3 + TypeScript + Vuetify 3, Bun, MySQL(retaku_admin/sv_nova), MongoDB(동적 연결), Sanctum 인증

---

## 참고 파일

| 역할 | 경로 |
|---|---|
| DriverConfig 컨트롤러 | `SeoulVenturesGroupware/app/Http/Controllers/Review/DriverConfigController.php` |
| DriverConfig 모델 | `SeoulVenturesGroupware/app/Models/Review/DriverConfig.php` |
| 채널 설정 페이지 (scanner) | `SeoulVenturesGroupware/frontend/resources/ts/pages/review/scanner/index.vue` |
| API 라우트 | `SeoulVenturesGroupware/routes/api.php` |
| API 클라이언트 | `SeoulVenturesGroupware/frontend/resources/ts/api/index.ts` |
| MongoDB 연결 서비스 | `SeoulVenturesGroupware/app/Services/MongoDB/MongoDBConnection.php` |
| MongoDB 컬렉션 리졸버 | `SeoulVenturesGroupware/app/Services/MongoDB/MongoDBCollectionResolver.php` |
| Mongo 모델 예시 | `SeoulVenturesGroupware/app/Models/Mongo/Review/UploadTargetList.php` |
| AlimtalkChannel | `SeoulVenturesGroupware/app/Services/Notification/Channels/AlimtalkChannel.php` |
| NotificationLog 모델 | `SeoulVenturesGroupware/app/Models/NotificationLog.php` |
| DailyReport 모델 | `SeoulVenturesGroupware/app/Models/Report/DailyReport.php` |
| DailyClientStatistic 모델 | `SeoulVenturesGroupware/app/Models/Report/DailyClientStatistic.php` |
| ReportGenerationService | `SeoulVenturesGroupware/app/Services/Report/ReportGenerationService.php` |
| GenerateDailyReportCommand | `SeoulVenturesGroupware/app/Console/Commands/GenerateDailyReportCommand.php` |
| 쿠팡 로켓 드라이버 | `review-moai-refactoring/app/drivers/download/CoupangRocketDriver.py:178-191` |
| 무신사 V2 드라이버 | `review-moai-refactoring/app/drivers/download/MusinsaV2Driver.py` |
| Nova MongoDBReviews 컨트롤러 | `sv-nova-master/app/Http/Controllers/Nova/MongoDBReviewsController.php` |
| Nova ReviewQueryService | `sv-nova-master/app/Services/Review/ReviewQueryService.php` |
| Nova NotificationSetting 모델 | `sv-nova-master/app/Models/NotificationSetting.php` |
| Nova ReportManagementController | `sv-nova-master/app/Http/Controllers/Nova/ReportManagementController.php` |

---

## Task 1: 무신사 체험단 리뷰 수집 모드 — 백엔드 테스트

**Files:**
- Create: `SeoulVenturesGroupware/tests/Feature/Review/DriverConfigMusinsaTest.php`

**Step 1: Write the failing test**

```php
<?php

namespace Tests\Feature\Review;

use App\Models\Review\Client;
use App\Models\Review\DownloadDriver;
use App\Models\Review\DriverConfig;
use App\Models\User;
use Laravel\Sanctum\Sanctum;
use Tests\TestCase;

class DriverConfigMusinsaTest extends TestCase
{
    public function test_update_include_experience_for_musinsa_v2(): void
    {
        $this->skipIfDatabaseUnavailable('retaku_admin');

        $user = User::factory()->create();
        Sanctum::actingAs($user);

        $client = Client::factory()->create();
        $driverConfig = DriverConfig::factory()->create([
            'client_id' => $client->id,
            'driver_code' => 'musinsa_v2',
            'driver_config' => ['profileUrl' => 'https://example.com'],
        ]);

        $response = $this->patchJson(
            "/api/review/clients/{$client->id}/driver-configs/{$driverConfig->id}",
            [
                'driver_config' => [
                    'profileUrl' => 'https://example.com',
                    'includeExperience' => true,
                ],
            ]
        );

        $response->assertOk();

        $driverConfig->refresh();
        $this->assertTrue($driverConfig->driver_config['includeExperience']);
        $this->assertEquals('https://example.com', $driverConfig->driver_config['profileUrl']);
    }

    public function test_include_experience_defaults_to_false_when_missing(): void
    {
        $this->skipIfDatabaseUnavailable('retaku_admin');

        $user = User::factory()->create();
        Sanctum::actingAs($user);

        $client = Client::factory()->create();
        $driverConfig = DriverConfig::factory()->create([
            'client_id' => $client->id,
            'driver_code' => 'musinsa_v2',
            'driver_config' => ['profileUrl' => 'https://example.com'],
        ]);

        $response = $this->getJson(
            "/api/review/clients/{$client->id}/driver-configs?per_page=100"
        );

        $response->assertOk();
        $configs = collect($response->json('data'));
        $config = $configs->firstWhere('id', $driverConfig->id);
        $this->assertFalse($config['driver_config']['includeExperience'] ?? false);
    }
}
```

**Step 2: Run test to verify it fails**

Run: `cd SeoulVenturesGroupware && vendor/bin/phpunit tests/Feature/Review/DriverConfigMusinsaTest.php -v`
Expected: PASS (기존 `DriverConfigController::update()`가 이미 `driver_config` 전체를 저장하므로 백엔드는 추가 작업 불필요)

**Step 3: Commit**

```bash
cd SeoulVenturesGroupware
git add tests/Feature/Review/DriverConfigMusinsaTest.php
git commit -m "test: 무신사 체험단 includeExperience 저장 테스트 추가"
```

---

## Task 2: 무신사 체험단 리뷰 수집 모드 — 프론트엔드

**Files:**
- Modify: `SeoulVenturesGroupware/frontend/resources/ts/pages/review/scanner/index.vue`

기존 scanner 페이지에서 `musinsa_v2` 드라이버의 채널 설정 행에 "체험단 리뷰 포함" Select 필드를 추가한다.

**Step 1: DriverConfig interface 확장**

`scanner/index.vue`의 `DriverConfig` interface에 `driver_code` 추가:

```typescript
interface DriverConfig {
  id: number
  driver_code: string  // 추가
  download_driver: {
    id: number
    name: string
    code: string       // 추가
    description: string
    spec: {
      profileUrl: string
    }
  }
  driver_config: {
    profileUrl?: string
    includeExperience?: boolean  // 추가
  }
}
```

`FormattedDriverConfig` interface 확장:

```typescript
interface FormattedDriverConfig {
  id: number
  channel: string
  driverCode: string                // 추가
  profileUrl: string
  description: string
  originalProfileUrl: string
  profileGuide: string
  includeExperience: boolean        // 추가
  originalIncludeExperience: boolean // 추가
}
```

**Step 2: formattedDriverConfigs 매핑 확장**

`updateFormattedDriverConfigs` 함수에 필드 추가:

```typescript
const updateFormattedDriverConfigs = () => {
  formattedDriverConfigs.value = driverConfigs.value.map(config => ({
    id: config.id,
    channel: config.download_driver.name,
    driverCode: config.driver_code,
    profileUrl: config.driver_config.profileUrl ?? '',
    description: config.download_driver.description,
    originalProfileUrl: config.driver_config.profileUrl ?? '',
    profileGuide: config.download_driver.spec?.profileUrl ?? '',
    includeExperience: config.driver_config.includeExperience ?? false,
    originalIncludeExperience: config.driver_config.includeExperience ?? false,
  }))
}
```

**Step 3: 저장 함수에 includeExperience 포함**

`saveProfileUrl` 함수를 `saveDriverConfig`로 리네임하고 includeExperience도 함께 저장:

```typescript
const saveDriverConfig = async (configId: number, item: FormattedDriverConfig) => {
  if (!selectedClient.value?.id) return

  const config = driverConfigs.value.find(c => c.id === configId)
  if (!config) return

  savingId.value = configId
  try {
    const driverConfigPayload: Record<string, unknown> = {
      ...config.driver_config,
      profileUrl: item.profileUrl,
    }

    // musinsa_v2만 includeExperience 포함
    if (config.driver_code === 'musinsa_v2') {
      driverConfigPayload.includeExperience = item.includeExperience
    }

    const { success, error } = await patch(
      `/review/clients/${selectedClient.value.id}/driver-configs/${configId}`,
      { driver_config: driverConfigPayload },
    )

    if (success) {
      config.driver_config = driverConfigPayload as DriverConfig['driver_config']
      item.originalProfileUrl = item.profileUrl
      item.originalIncludeExperience = item.includeExperience
      snackbar.success('설정이 저장되었습니다.')
    }
    else if (error) {
      handleError(error, { notificationMessage: '저장에 실패했습니다.' })
    }
  }
  catch (error) {
    handleError(error, { notificationMessage: '저장에 실패했습니다.' })
  }
  finally {
    savingId.value = null
  }
}
```

**Step 4: isChanged 함수 확장**

```typescript
const isChanged = (item: FormattedDriverConfig) => {
  return item.profileUrl !== item.originalProfileUrl
    || item.includeExperience !== item.originalIncludeExperience
}
```

**Step 5: 템플릿에 조건부 Select 추가**

`#item.profileUrl` 슬롯 내부, `<VTextField>` 아래에:

```html
<VSelect
  v-if="item.driverCode === 'musinsa_v2'"
  v-model="item.includeExperience"
  :items="[
    { title: '체험단 제외', value: false },
    { title: '체험단 포함', value: true },
  ]"
  density="compact"
  hide-details
  variant="outlined"
  label="체험단 리뷰"
  class="mt-2"
  style="max-width: 200px"
/>
```

저장 버튼 `@click` 변경: `saveProfileUrl(item.id, item.profileUrl)` → `saveDriverConfig(item.id, item)`

**Step 6: Commit**

```bash
cd SeoulVenturesGroupware/frontend && bun run typecheck
cd ..
git add frontend/resources/ts/pages/review/scanner/index.vue
git commit -m "feat: 무신사 체험단 리뷰 수집 모드 설정 UI 추가"
```

---

## Task 3: 쿠팡 판매자 필터 — 백엔드 테스트

**Files:**
- Create: `SeoulVenturesGroupware/tests/Feature/Review/DriverConfigCoupangTest.php`

**Step 1: Write the failing test**

```php
<?php

namespace Tests\Feature\Review;

use App\Models\Review\Client;
use App\Models\Review\DriverConfig;
use App\Models\User;
use Laravel\Sanctum\Sanctum;
use Tests\TestCase;

class DriverConfigCoupangTest extends TestCase
{
    public function test_update_seller_names_for_coupang_rocket(): void
    {
        $this->skipIfDatabaseUnavailable('retaku_admin');

        $user = User::factory()->create();
        Sanctum::actingAs($user);

        $client = Client::factory()->create();
        $driverConfig = DriverConfig::factory()->create([
            'client_id' => $client->id,
            'driver_code' => 'coupang_rocket',
            'driver_config' => ['profileUrl' => null],
        ]);

        $response = $this->patchJson(
            "/api/review/clients/{$client->id}/driver-configs/{$driverConfig->id}",
            [
                'driver_config' => [
                    'profileUrl' => null,
                    'sellerNames' => ['판매자A', '판매자B'],
                ],
            ]
        );

        $response->assertOk();

        $driverConfig->refresh();
        $this->assertEquals(['판매자A', '판매자B'], $driverConfig->driver_config['sellerNames']);
    }

    public function test_legacy_seller_name_string_preserved(): void
    {
        $this->skipIfDatabaseUnavailable('retaku_admin');

        $user = User::factory()->create();
        Sanctum::actingAs($user);

        $client = Client::factory()->create();
        $driverConfig = DriverConfig::factory()->create([
            'client_id' => $client->id,
            'driver_code' => 'coupang_rocket',
            'driver_config' => ['profileUrl' => null, 'sellerName' => '레거시판매자'],
        ]);

        // sellerNames로 업데이트하면 sellerName도 유지 (Python 드라이버 호환)
        $response = $this->patchJson(
            "/api/review/clients/{$client->id}/driver-configs/{$driverConfig->id}",
            [
                'driver_config' => [
                    'profileUrl' => null,
                    'sellerName' => '레거시판매자',
                    'sellerNames' => ['판매자A'],
                ],
            ]
        );

        $response->assertOk();
        $driverConfig->refresh();
        $this->assertEquals(['판매자A'], $driverConfig->driver_config['sellerNames']);
        $this->assertEquals('레거시판매자', $driverConfig->driver_config['sellerName']);
    }
}
```

**Step 2: Run test to verify it passes**

Run: `cd SeoulVenturesGroupware && vendor/bin/phpunit tests/Feature/Review/DriverConfigCoupangTest.php -v`
Expected: PASS (기존 `update()` 메서드가 `driver_config` 전체를 저장하므로 추가 작업 불필요)

**Step 3: Commit**

```bash
cd SeoulVenturesGroupware
git add tests/Feature/Review/DriverConfigCoupangTest.php
git commit -m "test: 쿠팡 판매자 필터 sellerNames 저장 테스트 추가"
```

---

## Task 4: 쿠팡 판매자 필터 — 프론트엔드

**Files:**
- Modify: `SeoulVenturesGroupware/frontend/resources/ts/pages/review/scanner/index.vue`

**Step 1: DriverConfig interface에 쿠팡 필드 추가**

```typescript
interface DriverConfig {
  // ... 기존 필드
  driver_config: {
    profileUrl?: string
    includeExperience?: boolean
    sellerName?: string | string[]    // 레거시
    sellerNames?: string[]            // 신규
  }
}

interface FormattedDriverConfig {
  // ... 기존 필드
  sellerNames: string[]               // 추가
  originalSellerNames: string[]        // 추가
}
```

**Step 2: formattedDriverConfigs 매핑에 sellerNames 추가**

```typescript
// updateFormattedDriverConfigs 내부
const parseSellerNames = (config: DriverConfig): string[] => {
  if (config.driver_config.sellerNames) return [...config.driver_config.sellerNames]
  if (config.driver_config.sellerName) {
    return Array.isArray(config.driver_config.sellerName)
      ? [...config.driver_config.sellerName]
      : [config.driver_config.sellerName]
  }
  return []
}

// map 내부에 추가:
sellerNames: parseSellerNames(config),
originalSellerNames: parseSellerNames(config),
```

**Step 3: saveDriverConfig에 sellerNames 포함**

`saveDriverConfig` 함수 내 `driverConfigPayload` 구성 부분:

```typescript
if (['coupang_rocket', 'coupang_rocket_v2'].includes(config.driver_code)) {
  driverConfigPayload.sellerNames = item.sellerNames
  // 레거시 sellerName 유지 (Python 드라이버 호환)
  if (config.driver_config.sellerName) {
    driverConfigPayload.sellerName = config.driver_config.sellerName
  }
}
```

성공 후:
```typescript
item.originalSellerNames = [...item.sellerNames]
```

**Step 4: isChanged에 sellerNames 비교 추가**

```typescript
const isChanged = (item: FormattedDriverConfig) => {
  return item.profileUrl !== item.originalProfileUrl
    || item.includeExperience !== item.originalIncludeExperience
    || JSON.stringify(item.sellerNames) !== JSON.stringify(item.originalSellerNames)
}
```

**Step 5: 템플릿에 쿠팡 판매자 입력 추가**

`#item.profileUrl` 슬롯 내부, musinsa Select 아래에:

```html
<div v-if="['coupang_rocket', 'coupang_rocket_v2'].includes(item.driverCode)" class="mt-2">
  <VCombobox
    v-model="item.sellerNames"
    :items="[]"
    multiple
    chips
    closable-chips
    density="compact"
    hide-details
    variant="outlined"
    label="판매자 필터"
    placeholder="판매자명 입력 후 Enter"
    style="max-width: 400px"
  />
  <small class="text-medium-emphasis">쿠팡(주)는 자동 포함됩니다. 추가 판매자만 입력하세요.</small>
</div>
```

**Step 6: Commit**

```bash
cd SeoulVenturesGroupware/frontend && bun run typecheck
cd ..
git add frontend/resources/ts/pages/review/scanner/index.vue
git commit -m "feat: 쿠팡 판매자 필터 설정 UI 추가"
```

---

## Task 5: NotificationSetting — 마이그레이션 & 모델

**Files:**
- Create: `SeoulVenturesGroupware/database/migrations/2026_02_27_000001_create_notification_settings_table.php`
- Create: `SeoulVenturesGroupware/app/Models/NotificationSetting.php`

**Step 1: Write the migration**

```php
<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    protected $connection = 'sv_nova';

    public function up(): void
    {
        if (Schema::connection('sv_nova')->hasTable('notification_settings')) {
            return;
        }

        Schema::connection('sv_nova')->create('notification_settings', function (Blueprint $table) {
            $table->id();
            $table->boolean('auto_notifications')->default(true);
            $table->string('daily_report_time')->nullable();
            $table->text('email_recipients')->nullable();
            $table->string('slack_webhook_url')->nullable();
            $table->boolean('alimtalk_enabled')->default(true);
            $table->boolean('email_enabled')->default(false);
            $table->boolean('slack_enabled')->default(false);
            $table->timestamps();
        });
    }

    public function down(): void
    {
        Schema::connection('sv_nova')->dropIfExists('notification_settings');
    }
};
```

**Step 2: Write the model**

```php
<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;

class NotificationSetting extends Model
{
    protected $connection = 'sv_nova';

    protected $table = 'notification_settings';

    protected $fillable = [
        'auto_notifications',
        'daily_report_time',
        'email_recipients',
        'slack_webhook_url',
        'alimtalk_enabled',
        'email_enabled',
        'slack_enabled',
    ];

    protected $casts = [
        'auto_notifications' => 'boolean',
        'alimtalk_enabled' => 'boolean',
        'email_enabled' => 'boolean',
        'slack_enabled' => 'boolean',
    ];

    public static function current(): self
    {
        return self::firstOrCreate([], [
            'auto_notifications' => true,
            'alimtalk_enabled' => true,
            'email_enabled' => false,
            'slack_enabled' => false,
        ]);
    }

    public function getEmailRecipientsArrayAttribute(): array
    {
        return $this->email_recipients
            ? array_map('trim', explode(',', $this->email_recipients))
            : [];
    }
}
```

**Step 3: Commit**

```bash
cd SeoulVenturesGroupware
git add database/migrations/2026_02_27_000001_create_notification_settings_table.php app/Models/NotificationSetting.php
git commit -m "feat: NotificationSetting 모델 및 마이그레이션 추가"
```

---

## Task 6: NotificationSetting — 컨트롤러 & 라우트 & 테스트

**Files:**
- Create: `SeoulVenturesGroupware/app/Http/Controllers/Api/Regle/NotificationSettingController.php`
- Modify: `SeoulVenturesGroupware/routes/api.php`
- Create: `SeoulVenturesGroupware/tests/Feature/Regle/NotificationSettingTest.php`

**Step 1: Write the failing tests**

```php
<?php

namespace Tests\Feature\Regle;

use App\Models\NotificationSetting;
use App\Models\User;
use Laravel\Sanctum\Sanctum;
use Tests\TestCase;

class NotificationSettingTest extends TestCase
{
    public function test_requires_auth(): void
    {
        $this->getJson('/api/regle/notification-settings')->assertStatus(401);
        $this->putJson('/api/regle/notification-settings')->assertStatus(401);
    }

    public function test_get_settings_returns_default_when_none_exists(): void
    {
        $this->skipIfDatabaseUnavailable('sv_nova');

        $user = User::factory()->create();
        Sanctum::actingAs($user);

        // 기존 레코드 삭제 (테스트 격리)
        NotificationSetting::query()->delete();

        $response = $this->getJson('/api/regle/notification-settings');

        $response->assertOk();
        $response->assertJsonFragment([
            'auto_notifications' => true,
            'alimtalk_enabled' => true,
            'email_enabled' => false,
            'slack_enabled' => false,
        ]);
    }

    public function test_update_settings(): void
    {
        $this->skipIfDatabaseUnavailable('sv_nova');

        $user = User::factory()->create();
        Sanctum::actingAs($user);

        $response = $this->putJson('/api/regle/notification-settings', [
            'auto_notifications' => false,
            'daily_report_time' => '09:00',
            'email_recipients' => 'a@test.com, b@test.com',
            'alimtalk_enabled' => false,
        ]);

        $response->assertOk();

        $setting = NotificationSetting::current();
        $this->assertFalse($setting->auto_notifications);
        $this->assertEquals('09:00', $setting->daily_report_time);
        $this->assertFalse($setting->alimtalk_enabled);
    }

    public function test_update_validates_email_recipients(): void
    {
        $this->skipIfDatabaseUnavailable('sv_nova');

        $user = User::factory()->create();
        Sanctum::actingAs($user);

        $response = $this->putJson('/api/regle/notification-settings', [
            'daily_report_time' => 'invalid',
        ]);

        $response->assertStatus(422);
    }
}
```

**Step 2: Run tests to verify they fail**

Run: `cd SeoulVenturesGroupware && vendor/bin/phpunit tests/Feature/Regle/NotificationSettingTest.php -v`
Expected: FAIL (404 — 라우트/컨트롤러 미존재)

**Step 3: Write the controller**

```php
<?php

namespace App\Http\Controllers\Api\Regle;

use App\Http\Controllers\Controller;
use App\Models\NotificationSetting;
use Illuminate\Http\Request;

class NotificationSettingController extends Controller
{
    public function show()
    {
        return response()->json(NotificationSetting::current());
    }

    public function update(Request $request)
    {
        $validated = $request->validate([
            'auto_notifications' => 'sometimes|boolean',
            'daily_report_time' => 'nullable|date_format:H:i',
            'email_recipients' => 'nullable|string',
            'slack_webhook_url' => 'nullable|url',
            'alimtalk_enabled' => 'sometimes|boolean',
            'email_enabled' => 'sometimes|boolean',
            'slack_enabled' => 'sometimes|boolean',
        ]);

        $setting = NotificationSetting::current();
        $setting->fill($validated);
        $setting->save();

        return response()->json($setting);
    }

    public function testNotification(Request $request)
    {
        $validated = $request->validate([
            'channel' => 'required|in:email,slack,alimtalk',
        ]);

        $setting = NotificationSetting::current();

        $result = match ($validated['channel']) {
            'email' => $this->sendTestEmail($setting),
            'slack' => $this->sendTestSlack($setting),
            'alimtalk' => ['success' => false, 'message' => '알림톡 테스트는 준비 중입니다.'],
        };

        return response()->json($result);
    }

    private function sendTestEmail(NotificationSetting $setting): array
    {
        $recipients = $setting->email_recipients_array;
        if (empty($recipients)) {
            return ['success' => false, 'message' => '수신자 이메일이 설정되지 않았습니다.'];
        }

        try {
            \Illuminate\Support\Facades\Mail::raw('알림 설정 테스트 메일입니다.', function ($message) use ($recipients) {
                $message->to($recipients)->subject('[Regle] 알림 테스트');
            });
            return ['success' => true, 'message' => '테스트 이메일이 발송되었습니다.'];
        } catch (\Throwable $e) {
            return ['success' => false, 'message' => '이메일 발송 실패: ' . $e->getMessage()];
        }
    }

    private function sendTestSlack(NotificationSetting $setting): array
    {
        if (!$setting->slack_webhook_url) {
            return ['success' => false, 'message' => 'Slack Webhook URL이 설정되지 않았습니다.'];
        }

        try {
            \Illuminate\Support\Facades\Http::post($setting->slack_webhook_url, [
                'text' => '[Regle] 알림 설정 테스트 메시지입니다.',
            ]);
            return ['success' => true, 'message' => '테스트 Slack 메시지가 발송되었습니다.'];
        } catch (\Throwable $e) {
            return ['success' => false, 'message' => 'Slack 발송 실패: ' . $e->getMessage()];
        }
    }
}
```

**Step 4: Add routes**

`routes/api.php`의 `auth:sanctum` 미들웨어 그룹 내, `regle` prefix 그룹에 추가:

```php
use App\Http\Controllers\Api\Regle\NotificationSettingController;

// regle prefix 그룹 내부
Route::get('notification-settings', [NotificationSettingController::class, 'show']);
Route::put('notification-settings', [NotificationSettingController::class, 'update']);
Route::post('notification-settings/test', [NotificationSettingController::class, 'testNotification']);
```

**Step 5: Run tests to verify they pass**

Run: `cd SeoulVenturesGroupware && vendor/bin/phpunit tests/Feature/Regle/NotificationSettingTest.php -v`
Expected: PASS

**Step 6: Commit**

```bash
cd SeoulVenturesGroupware
git add app/Http/Controllers/Api/Regle/NotificationSettingController.php routes/api.php tests/Feature/Regle/NotificationSettingTest.php
git commit -m "feat: NotificationSetting API 컨트롤러 및 라우트 추가"
```

---

## Task 7: NotificationSetting — 프론트엔드 페이지

**Files:**
- Create: `SeoulVenturesGroupware/frontend/resources/ts/pages/regle/notification-settings/index.vue`
- Create: `SeoulVenturesGroupware/frontend/resources/ts/api/entities/regle/notificationSettings.ts`

**Step 1: API 엔티티 생성**

```typescript
import { type ApiResponse, get, post, put } from '@/api'

export interface NotificationSettingData {
  id: number
  auto_notifications: boolean
  daily_report_time: string | null
  email_recipients: string | null
  slack_webhook_url: string | null
  alimtalk_enabled: boolean
  email_enabled: boolean
  slack_enabled: boolean
}

export const notificationSettingsApi = {
  get: (): Promise<ApiResponse<NotificationSettingData>> =>
    get('/regle/notification-settings'),

  update: (data: Partial<NotificationSettingData>): Promise<ApiResponse<NotificationSettingData>> =>
    put('/regle/notification-settings', data),

  test: (channel: 'email' | 'slack' | 'alimtalk'): Promise<ApiResponse<{ success: boolean; message: string }>> =>
    post('/regle/notification-settings/test', { channel }),
}
```

**Step 2: 페이지 컴포넌트 생성**

```vue
<script setup lang="ts">
import { ref, onMounted } from 'vue'
import { notificationSettingsApi, type NotificationSettingData } from '@/api/entities/regle/notificationSettings'

definePage({
  meta: {
    title: '알림 설정',
    action: 'manage',
    subject: 'NotificationSetting',
  },
})

const { snackbar, handleError } = useErrorHandler()

const loading = ref(false)
const saving = ref(false)
const testingChannel = ref<string | null>(null)
const settings = ref<NotificationSettingData>({
  id: 0,
  auto_notifications: true,
  daily_report_time: null,
  email_recipients: null,
  slack_webhook_url: null,
  alimtalk_enabled: true,
  email_enabled: false,
  slack_enabled: false,
})

const loadSettings = async () => {
  loading.value = true
  try {
    const { success, data, error } = await notificationSettingsApi.get()
    if (success && data) settings.value = data
    else if (error) handleError(error, { notificationMessage: '설정을 불러오는데 실패했습니다.' })
  } catch (error) {
    handleError(error, { notificationMessage: '설정을 불러오는데 실패했습니다.' })
  } finally {
    loading.value = false
  }
}

const saveSettings = async () => {
  saving.value = true
  try {
    const { success, data, error } = await notificationSettingsApi.update(settings.value)
    if (success && data) {
      settings.value = data
      snackbar.success('설정이 저장되었습니다.')
    } else if (error) {
      handleError(error, { notificationMessage: '저장에 실패했습니다.' })
    }
  } catch (error) {
    handleError(error, { notificationMessage: '저장에 실패했습니다.' })
  } finally {
    saving.value = false
  }
}

const sendTest = async (channel: 'email' | 'slack' | 'alimtalk') => {
  testingChannel.value = channel
  try {
    const { success, data, error } = await notificationSettingsApi.test(channel)
    if (success && data) {
      if (data.success) snackbar.success(data.message)
      else snackbar.error(data.message)
    } else if (error) {
      handleError(error, { notificationMessage: '테스트 발송에 실패했습니다.' })
    }
  } catch (error) {
    handleError(error, { notificationMessage: '테스트 발송에 실패했습니다.' })
  } finally {
    testingChannel.value = null
  }
}

onMounted(loadSettings)
</script>

<template>
  <VRow>
    <VCol cols="12" md="6">
      <VCard :loading="loading">
        <VCardTitle>일반 설정</VCardTitle>
        <VCardText>
          <VSwitch
            v-model="settings.auto_notifications"
            label="자동 알림 활성화"
            color="primary"
            hide-details
            class="mb-4"
          />
          <VTextField
            v-model="settings.daily_report_time"
            label="일일 리포트 발송 시간"
            placeholder="09:00"
            hint="HH:MM 형식"
            persistent-hint
            variant="outlined"
            density="compact"
          />
        </VCardText>
      </VCard>
    </VCol>

    <VCol cols="12" md="6">
      <VCard>
        <VCardTitle>채널 설정</VCardTitle>
        <VCardText>
          <VSwitch
            v-model="settings.alimtalk_enabled"
            label="알림톡"
            color="primary"
            hide-details
            class="mb-2"
          />
          <VSwitch
            v-model="settings.email_enabled"
            label="이메일"
            color="primary"
            hide-details
            class="mb-2"
          />
          <VSwitch
            v-model="settings.slack_enabled"
            label="Slack"
            color="primary"
            hide-details
          />
        </VCardText>
      </VCard>
    </VCol>

    <VCol cols="12" md="6">
      <VCard>
        <VCardTitle>수신자 설정</VCardTitle>
        <VCardText>
          <VTextarea
            v-model="settings.email_recipients"
            label="이메일 수신자"
            placeholder="admin@example.com, user@example.com"
            hint="쉼표로 구분하여 입력"
            persistent-hint
            variant="outlined"
            density="compact"
            rows="3"
            class="mb-4"
          />
          <VTextField
            v-model="settings.slack_webhook_url"
            label="Slack Webhook URL"
            placeholder="https://hooks.slack.com/services/..."
            variant="outlined"
            density="compact"
          />
        </VCardText>
      </VCard>
    </VCol>

    <VCol cols="12" md="6">
      <VCard>
        <VCardTitle>테스트 발송</VCardTitle>
        <VCardText>
          <div class="d-flex gap-2 flex-wrap">
            <VBtn
              color="primary"
              variant="outlined"
              :loading="testingChannel === 'email'"
              :disabled="!settings.email_enabled || testingChannel !== null"
              @click="sendTest('email')"
            >
              이메일 테스트
            </VBtn>
            <VBtn
              color="primary"
              variant="outlined"
              :loading="testingChannel === 'slack'"
              :disabled="!settings.slack_enabled || testingChannel !== null"
              @click="sendTest('slack')"
            >
              Slack 테스트
            </VBtn>
          </div>
        </VCardText>
      </VCard>
    </VCol>

    <VCol cols="12">
      <div class="d-flex justify-end">
        <VBtn
          color="primary"
          :loading="saving"
          @click="saveSettings"
        >
          설정 저장
        </VBtn>
      </div>
    </VCol>
  </VRow>
</template>
```

**Step 3: Commit**

```bash
cd SeoulVenturesGroupware
git add frontend/resources/ts/api/entities/regle/notificationSettings.ts frontend/resources/ts/pages/regle/notification-settings/index.vue
git commit -m "feat: NotificationSetting 프론트엔드 설정 페이지 추가"
```

---

## Task 8: MongoDB 리뷰 조회 — 서비스 & 모델

**Files:**
- Create: `SeoulVenturesGroupware/app/Models/Mongo/Review/StandardReviewTarget.php`
- Create: `SeoulVenturesGroupware/app/Services/Review/ReviewQueryService.php`

**Step 1: MongoDB 모델 생성**

```php
<?php

namespace App\Models\Mongo\Review;

use MongoDB\Laravel\Eloquent\Model;

class StandardReviewTarget extends Model
{
    protected $collection = 'standard_review_target';
    protected $connection = 'mongodb';
}
```

**Step 2: ReviewQueryService 생성**

```php
<?php

namespace App\Services\Review;

use App\Models\Review\Client;
use App\Models\Review\ClientItem;
use App\Models\Review\Target;
use App\Models\Review\TargetItemMap;
use App\Services\MongoDB\MongoDBConnection;
use App\Services\MongoDB\MongoDBCollectionResolver;
use Illuminate\Support\Facades\Cache;

class ReviewQueryService
{
    public function __construct(
        private MongoDBConnection $mongoConnection,
        private MongoDBCollectionResolver $collectionResolver,
    ) {}

    public function getReviews(string $resourceType, int $resourceId, array $filters = [], int $page = 1, int $perPage = 20): array
    {
        [$client, $conditions] = $this->resolveQueryConditions($resourceType, $resourceId);

        if (!$client || !$client->target_database_hive) {
            return ['data' => [], 'total' => 0, 'page' => $page, 'per_page' => $perPage];
        }

        $connection = $this->mongoConnection->getConnectionFor($client);
        $query = $connection->table($this->collectionResolver->resolveStandardReview());

        foreach ($conditions as $field => $value) {
            $query->where($field, $value);
        }

        $this->applyFilters($query, $filters);

        $sortBy = $filters['sort_by'] ?? 'review_reg_date';
        $sortDir = $filters['sort_direction'] ?? 'desc';
        $query->orderBy($sortBy, $sortDir);

        $total = (clone $query)->count();

        $reviews = $query
            ->skip(($page - 1) * $perPage)
            ->take($perPage)
            ->get()
            ->map(fn ($review) => $this->formatReview($review))
            ->toArray();

        return [
            'data' => $reviews,
            'total' => $total,
            'page' => $page,
            'per_page' => $perPage,
        ];
    }

    public function getStats(string $resourceType, int $resourceId): array
    {
        $cacheKey = "review_stats_{$resourceType}_{$resourceId}";

        return Cache::remember($cacheKey, 300, function () use ($resourceType, $resourceId) {
            [$client, $conditions] = $this->resolveQueryConditions($resourceType, $resourceId);

            if (!$client || !$client->target_database_hive) {
                return ['total_reviews' => 0, 'score_distribution' => [], 'type_distribution' => []];
            }

            $connection = $this->mongoConnection->getConnectionFor($client);
            $collection = $this->collectionResolver->resolveStandardReview();
            $query = $connection->table($collection);

            foreach ($conditions as $field => $value) {
                $query->where($field, $value);
            }

            $total = (clone $query)->count();

            $scoreDistribution = [];
            for ($i = 1; $i <= 5; $i++) {
                $scoreDistribution[(string) $i] = (clone $query)->where('review_score', $i)->count();
            }

            $typeDistribution = [
                'text' => (clone $query)->where('review_type', 'text')->count(),
                'photo' => (clone $query)->where('review_type', 'photo')->count(),
            ];

            return [
                'total_reviews' => $total,
                'score_distribution' => $scoreDistribution,
                'type_distribution' => $typeDistribution,
            ];
        });
    }

    private function resolveQueryConditions(string $resourceType, int $resourceId): array
    {
        return match ($resourceType) {
            'targets' => $this->resolveForTarget($resourceId),
            'target-item-maps' => $this->resolveForTargetItemMap($resourceId),
            'client-items' => $this->resolveForClientItem($resourceId),
            default => [null, []],
        };
    }

    private function resolveForTarget(int $targetId): array
    {
        $target = Target::with('driverConfig.client')->findOrFail($targetId);
        $client = $target->driverConfig->client;
        return [$client, ['target_item_code' => $target->product_id]];
    }

    private function resolveForTargetItemMap(int $mapId): array
    {
        $map = TargetItemMap::with(['target.driverConfig.client'])->findOrFail($mapId);
        $client = $map->target->driverConfig->client;
        return [$client, [
            'client_item_code' => $map->client_item_code,
            'target_item_code' => $map->target_item_code,
        ]];
    }

    private function resolveForClientItem(int $clientItemId): array
    {
        $item = ClientItem::with('client')->findOrFail($clientItemId);
        return [$item->client, ['client_item_code' => $item->item_code]];
    }

    private function applyFilters($query, array $filters): void
    {
        if (!empty($filters['start_date'])) {
            $query->where('review_reg_date', '>=', $filters['start_date']);
        }
        if (!empty($filters['end_date'])) {
            $query->where('review_reg_date', '<=', $filters['end_date'] . ' 23:59:59');
        }
        if (!empty($filters['score'])) {
            $query->where('review_score', (int) $filters['score']);
        }
        if (!empty($filters['review_type']) && $filters['review_type'] !== 'all') {
            $query->where('review_type', $filters['review_type']);
        }
    }

    private function formatReview($review): array
    {
        return [
            '_id' => (string) ($review['_id'] ?? ''),
            'review_user_name' => $review['review_user_name'] ?? '',
            'review_reg_date' => $review['review_reg_date'] ?? '',
            'review_content' => $review['review_content'] ?? '',
            'review_score' => $review['review_score'] ?? 0,
            'review_type' => $review['review_type'] ?? 'text',
            'review_images' => $review['review_images'] ?? [],
            'client_item_code' => $review['client_item_code'] ?? '',
            'target_item_code' => $review['target_item_code'] ?? '',
            'upload_key' => $review['upload_key'] ?? '',
            'crawling_date' => $review['crawling_date'] ?? '',
            'deleted' => $review['deleted'] ?? false,
            'delete_status' => $review['delete_status'] ?? null,
            'delete_reason' => $review['delete_reason'] ?? null,
        ];
    }
}
```

**Step 3: Commit**

```bash
cd SeoulVenturesGroupware
git add app/Models/Mongo/Review/StandardReviewTarget.php app/Services/Review/ReviewQueryService.php
git commit -m "feat: MongoDB 리뷰 조회 서비스 및 모델 추가"
```

---

## Task 9: MongoDB 리뷰 조회 — 컨트롤러 & 라우트 & 테스트

**Files:**
- Create: `SeoulVenturesGroupware/app/Http/Controllers/Review/ReviewMongoController.php`
- Modify: `SeoulVenturesGroupware/routes/api.php`
- Create: `SeoulVenturesGroupware/tests/Feature/Review/ReviewMongoControllerTest.php`

**Step 1: Write the failing tests**

```php
<?php

namespace Tests\Feature\Review;

use App\Models\User;
use Laravel\Sanctum\Sanctum;
use Tests\TestCase;

class ReviewMongoControllerTest extends TestCase
{
    public function test_requires_auth(): void
    {
        $this->getJson('/api/review/mongodb-reviews/targets/1')->assertStatus(401);
        $this->getJson('/api/review/mongodb-reviews/targets/1/stats')->assertStatus(401);
    }

    public function test_validates_resource_type(): void
    {
        $user = User::factory()->create();
        Sanctum::actingAs($user);

        $this->getJson('/api/review/mongodb-reviews/invalid/1')->assertStatus(422);
    }

    public function test_validates_query_params(): void
    {
        $user = User::factory()->create();
        Sanctum::actingAs($user);

        $this->getJson('/api/review/mongodb-reviews/targets/1?per_page=999')
            ->assertStatus(422);
    }
}
```

**Step 2: Write the controller**

```php
<?php

namespace App\Http\Controllers\Review;

use App\Http\Controllers\Controller;
use App\Services\Review\ReviewQueryService;
use Illuminate\Http\Request;

class ReviewMongoController extends Controller
{
    public function __construct(
        private ReviewQueryService $reviewQueryService,
    ) {}

    public function index(Request $request, string $resourceType, int $resourceId)
    {
        $request->validate([
            'page' => 'integer|min:1',
            'per_page' => 'integer|min:1|max:100',
            'start_date' => 'nullable|date',
            'end_date' => 'nullable|date',
            'score' => 'nullable|integer|min:1|max:5',
            'review_type' => 'nullable|in:text,photo,video,all',
            'sort_by' => 'nullable|in:review_reg_date,review_score,crawling_date',
            'sort_direction' => 'nullable|in:asc,desc',
        ]);

        $this->validateResourceType($resourceType);

        try {
            $result = $this->reviewQueryService->getReviews(
                $resourceType,
                $resourceId,
                $request->only(['start_date', 'end_date', 'score', 'review_type', 'sort_by', 'sort_direction']),
                $request->integer('page', 1),
                $request->integer('per_page', 20),
            );

            return response()->json($result);
        } catch (\Illuminate\Database\Eloquent\ModelNotFoundException $e) {
            return response()->json(['message' => '리소스를 찾을 수 없습니다.'], 404);
        } catch (\Throwable $e) {
            return response()->json(['message' => 'MongoDB 연결에 실패했습니다.', 'error' => $e->getMessage()], 503);
        }
    }

    public function stats(Request $request, string $resourceType, int $resourceId)
    {
        $this->validateResourceType($resourceType);

        try {
            $result = $this->reviewQueryService->getStats($resourceType, $resourceId);
            return response()->json($result);
        } catch (\Illuminate\Database\Eloquent\ModelNotFoundException $e) {
            return response()->json(['message' => '리소스를 찾을 수 없습니다.'], 404);
        } catch (\Throwable $e) {
            return response()->json(['message' => 'MongoDB 연결에 실패했습니다.'], 503);
        }
    }

    private function validateResourceType(string $resourceType): void
    {
        if (!in_array($resourceType, ['targets', 'target-item-maps', 'client-items'])) {
            abort(422, '유효하지 않은 리소스 타입입니다.');
        }
    }
}
```

**Step 3: Add routes**

`routes/api.php`의 `review` prefix 그룹 내:

```php
use App\Http\Controllers\Review\ReviewMongoController;

Route::get('mongodb-reviews/{resourceType}/{resourceId}', [ReviewMongoController::class, 'index']);
Route::get('mongodb-reviews/{resourceType}/{resourceId}/stats', [ReviewMongoController::class, 'stats']);
```

**Step 4: Run tests**

Run: `cd SeoulVenturesGroupware && vendor/bin/phpunit tests/Feature/Review/ReviewMongoControllerTest.php -v`
Expected: PASS

**Step 5: Commit**

```bash
cd SeoulVenturesGroupware
git add app/Http/Controllers/Review/ReviewMongoController.php routes/api.php tests/Feature/Review/ReviewMongoControllerTest.php
git commit -m "feat: MongoDB 리뷰 조회 API 컨트롤러 및 라우트 추가"
```

---

## Task 10: MongoDB 리뷰 조회 — 프론트엔드

**Files:**
- Create: `SeoulVenturesGroupware/frontend/resources/ts/api/entities/review/mongoReviews.ts`
- Create: `SeoulVenturesGroupware/frontend/resources/ts/components/review/MongoReviewList.vue`
- Create: `SeoulVenturesGroupware/frontend/resources/ts/components/review/MongoReviewFilters.vue`
- Create: `SeoulVenturesGroupware/frontend/resources/ts/components/review/MongoReviewDialog.vue`

**Step 1: API 엔티티 생성**

```typescript
// mongoReviews.ts
import { type ApiResponse, get } from '@/api'

export interface MongoReview {
  _id: string
  review_user_name: string
  review_reg_date: string
  review_content: string
  review_score: number
  review_type: string
  review_images: string[]
  client_item_code: string
  target_item_code: string
  upload_key: string
  crawling_date: string
  deleted: boolean
  delete_status: string | null
  delete_reason: string | null
}

export interface MongoReviewStats {
  total_reviews: number
  score_distribution: Record<string, number>
  type_distribution: Record<string, number>
}

export interface MongoReviewFilters {
  start_date?: string
  end_date?: string
  score?: number
  review_type?: string
  sort_by?: string
  sort_direction?: string
}

export const mongoReviewsApi = {
  list: (resourceType: string, resourceId: number, filters?: MongoReviewFilters & { page?: number; per_page?: number }): Promise<ApiResponse<{ data: MongoReview[]; total: number; page: number; per_page: number }>> =>
    get(`/review/mongodb-reviews/${resourceType}/${resourceId}`, filters as Record<string, unknown>),

  stats: (resourceType: string, resourceId: number): Promise<ApiResponse<MongoReviewStats>> =>
    get(`/review/mongodb-reviews/${resourceType}/${resourceId}/stats`),
}
```

**Step 2: MongoReviewDialog 컴포넌트**

이 컴포넌트는 Target/TargetItemMap/ClientItem 상세에서 "리뷰 원본 보기" 버튼 클릭 시 열리는 다이얼로그입니다. 내부에 필터, 통계 카드, 리뷰 목록을 포함합니다.

```vue
<!-- MongoReviewDialog.vue -->
<script setup lang="ts">
import { ref, watch } from 'vue'
import { mongoReviewsApi, type MongoReview, type MongoReviewStats, type MongoReviewFilters } from '@/api/entities/review/mongoReviews'

const props = defineProps<{
  modelValue: boolean
  resourceType: string
  resourceId: number
}>()

const emit = defineEmits<{
  'update:modelValue': [value: boolean]
}>()

const { handleError } = useErrorHandler()

const loading = ref(false)
const reviews = ref<MongoReview[]>([])
const stats = ref<MongoReviewStats | null>(null)
const total = ref(0)
const page = ref(1)
const perPage = ref(20)
const filters = ref<MongoReviewFilters>({
  sort_by: 'review_reg_date',
  sort_direction: 'desc',
})

const loadReviews = async () => {
  loading.value = true
  try {
    const { success, data, error } = await mongoReviewsApi.list(
      props.resourceType, props.resourceId,
      { ...filters.value, page: page.value, per_page: perPage.value },
    )
    if (success && data) {
      reviews.value = data.data
      total.value = data.total
    } else if (error) {
      handleError(error, { notificationMessage: '리뷰를 불러오는데 실패했습니다.' })
    }
  } catch (error) {
    handleError(error, { notificationMessage: '리뷰를 불러오는데 실패했습니다.' })
  } finally {
    loading.value = false
  }
}

const loadStats = async () => {
  try {
    const { success, data } = await mongoReviewsApi.stats(props.resourceType, props.resourceId)
    if (success && data) stats.value = data
  } catch { /* 통계 실패는 무시 */ }
}

const applyFilters = (newFilters: MongoReviewFilters) => {
  filters.value = newFilters
  page.value = 1
  loadReviews()
}

const scoreStars = (score: number) => '★'.repeat(score) + '☆'.repeat(5 - score)

const headers = [
  { title: '작성자', key: 'review_user_name', width: '100px' },
  { title: '점수', key: 'review_score', width: '120px' },
  { title: '내용', key: 'review_content' },
  { title: '타입', key: 'review_type', width: '80px' },
  { title: '작성일', key: 'review_reg_date', width: '160px' },
]

watch(() => props.modelValue, (val) => {
  if (val) {
    page.value = 1
    loadReviews()
    loadStats()
  }
})
</script>

<template>
  <VDialog
    :model-value="modelValue"
    max-width="1200"
    scrollable
    @update:model-value="emit('update:modelValue', $event)"
  >
    <VCard>
      <VCardTitle class="d-flex align-center justify-space-between">
        <span>리뷰 원본 데이터</span>
        <VBtn icon="tabler-x" variant="text" @click="emit('update:modelValue', false)" />
      </VCardTitle>

      <VCardText>
        <!-- 통계 카드 -->
        <VRow v-if="stats" class="mb-4">
          <VCol cols="4">
            <VCard variant="outlined">
              <VCardText class="text-center">
                <div class="text-h5">{{ stats.total_reviews.toLocaleString() }}</div>
                <div class="text-caption">총 리뷰</div>
              </VCardText>
            </VCard>
          </VCol>
          <VCol cols="4">
            <VCard variant="outlined">
              <VCardText class="text-center">
                <div class="text-h5">{{ stats.type_distribution.photo ?? 0 }}</div>
                <div class="text-caption">포토 리뷰</div>
              </VCardText>
            </VCard>
          </VCol>
          <VCol cols="4">
            <VCard variant="outlined">
              <VCardText class="text-center">
                <div class="text-h5">{{ stats.type_distribution.text ?? 0 }}</div>
                <div class="text-caption">텍스트 리뷰</div>
              </VCardText>
            </VCard>
          </VCol>
        </VRow>

        <!-- 필터 -->
        <VRow class="mb-4" dense>
          <VCol cols="12" md="2">
            <VTextField v-model="filters.start_date" type="date" label="시작일" density="compact" variant="outlined" hide-details />
          </VCol>
          <VCol cols="12" md="2">
            <VTextField v-model="filters.end_date" type="date" label="종료일" density="compact" variant="outlined" hide-details />
          </VCol>
          <VCol cols="12" md="2">
            <VSelect
              v-model="filters.score"
              :items="[{ title: '전체', value: undefined }, ...Array.from({length: 5}, (_, i) => ({ title: `${i+1}점`, value: i+1 }))]"
              label="점수"
              density="compact"
              variant="outlined"
              hide-details
            />
          </VCol>
          <VCol cols="12" md="2">
            <VSelect
              v-model="filters.review_type"
              :items="[{ title: '전체', value: 'all' }, { title: '텍스트', value: 'text' }, { title: '사진', value: 'photo' }]"
              label="타입"
              density="compact"
              variant="outlined"
              hide-details
            />
          </VCol>
          <VCol cols="12" md="2">
            <VSelect
              v-model="filters.sort_by"
              :items="[{ title: '작성일', value: 'review_reg_date' }, { title: '점수', value: 'review_score' }, { title: '수집일', value: 'crawling_date' }]"
              label="정렬"
              density="compact"
              variant="outlined"
              hide-details
            />
          </VCol>
          <VCol cols="12" md="2" class="d-flex align-center">
            <VBtn color="primary" variant="outlined" density="compact" @click="applyFilters(filters)">검색</VBtn>
          </VCol>
        </VRow>

        <!-- 리뷰 테이블 -->
        <VDataTable
          :headers="headers"
          :items="reviews"
          :loading="loading"
          density="compact"
          :items-per-page="perPage"
          hide-default-footer
        >
          <template #item.review_score="{ item }">
            <span class="text-warning">{{ scoreStars(item.review_score) }}</span>
          </template>
          <template #item.review_content="{ item }">
            <div class="text-truncate" style="max-width: 400px">
              <VChip v-if="item.deleted" color="error" size="x-small" class="me-1">삭제됨</VChip>
              {{ item.review_content }}
            </div>
          </template>
          <template #item.review_type="{ item }">
            <VChip :color="item.review_type === 'photo' ? 'primary' : 'default'" size="small">
              {{ item.review_type === 'photo' ? '사진' : '텍스트' }}
            </VChip>
          </template>
          <template #no-data>
            <div class="text-center pa-4">리뷰 데이터가 없습니다.</div>
          </template>
        </VDataTable>

        <!-- 페이지네이션 -->
        <div class="d-flex justify-center mt-4">
          <VPagination
            v-model="page"
            :length="Math.ceil(total / perPage)"
            :total-visible="7"
            @update:model-value="loadReviews"
          />
        </div>
      </VCardText>
    </VCard>
  </VDialog>
</template>
```

**Step 3: Commit**

```bash
cd SeoulVenturesGroupware
git add frontend/resources/ts/api/entities/review/mongoReviews.ts frontend/resources/ts/components/review/MongoReviewDialog.vue
git commit -m "feat: MongoDB 리뷰 조회 프론트엔드 컴포넌트 추가"
```

---

## Task 11: DailyReport 목록/상세 — 컨트롤러 & 라우트 & 테스트

**Files:**
- Create: `SeoulVenturesGroupware/app/Http/Controllers/Review/DailyReportController.php`
- Modify: `SeoulVenturesGroupware/routes/api.php`
- Create: `SeoulVenturesGroupware/tests/Feature/Review/DailyReportControllerTest.php`

**Step 1: Write the failing tests**

```php
<?php

namespace Tests\Feature\Review;

use App\Models\User;
use Laravel\Sanctum\Sanctum;
use Tests\TestCase;

class DailyReportControllerTest extends TestCase
{
    public function test_index_requires_auth(): void
    {
        $this->getJson('/api/review/daily-reports')->assertStatus(401);
    }

    public function test_generate_requires_auth(): void
    {
        $this->postJson('/api/review/daily-reports/generate')->assertStatus(401);
    }

    public function test_index_returns_paginated_reports(): void
    {
        $this->skipIfDatabaseUnavailable('sv_nova');

        $user = User::factory()->create();
        Sanctum::actingAs($user);

        $response = $this->getJson('/api/review/daily-reports?per_page=10');
        $response->assertOk();
        $response->assertJsonStructure(['data', 'current_page', 'per_page']);
    }

    public function test_generate_validates_date(): void
    {
        $this->skipIfDatabaseUnavailable('sv_nova');

        $user = User::factory()->create();
        Sanctum::actingAs($user);

        $response = $this->postJson('/api/review/daily-reports/generate', [
            'date' => 'invalid-date',
        ]);
        $response->assertStatus(422);
    }
}
```

**Step 2: Write the controller**

```php
<?php

namespace App\Http\Controllers\Review;

use App\Http\Controllers\Controller;
use App\Models\Report\DailyReport;
use App\Services\Report\ReportGenerationService;
use Illuminate\Http\Request;
use Illuminate\Support\Carbon;

class DailyReportController extends Controller
{
    public function __construct(
        private ReportGenerationService $reportService,
    ) {}

    public function index(Request $request)
    {
        $query = DailyReport::query()->with(['clientStatistics', 'driverStatistics']);

        if ($request->filled('start_date')) {
            $query->where('report_date', '>=', $request->input('start_date'));
        }
        if ($request->filled('end_date')) {
            $query->where('report_date', '<=', $request->input('end_date'));
        }

        return $query->orderByDesc('report_date')
            ->paginate($request->integer('per_page', 20));
    }

    public function show(int $id)
    {
        $report = DailyReport::with(['clientStatistics', 'driverStatistics'])->findOrFail($id);
        return response()->json($report);
    }

    public function generate(Request $request)
    {
        $validated = $request->validate([
            'date' => 'required|date_format:Y-m-d',
            'force' => 'boolean',
        ]);

        $date = Carbon::parse($validated['date']);
        $force = $validated['force'] ?? false;

        $existing = DailyReport::whereDate('report_date', $date)->first();
        if ($existing && !$force) {
            return response()->json([
                'message' => '해당 날짜의 리포트가 이미 존재합니다.',
                'existing_id' => $existing->id,
            ], 409);
        }

        try {
            $report = $this->reportService->generateDailyReport($date);
            return response()->json(['message' => '리포트가 생성되었습니다.', 'report' => $report], 201);
        } catch (\Throwable $e) {
            return response()->json(['message' => '리포트 생성에 실패했습니다.', 'error' => $e->getMessage()], 500);
        }
    }

    public function analytics()
    {
        $reports = DailyReport::where('report_date', '>=', now()->subDays(30))
            ->orderBy('report_date')
            ->get(['report_date', 'total_reviews', 'transferred_reviews', 'failed_reviews', 'success_rate', 'active_clients']);

        return response()->json($reports);
    }

    public function download(int $id)
    {
        $report = DailyReport::with(['clientStatistics', 'driverStatistics'])->findOrFail($id);

        $filename = "daily_report_{$report->report_date->format('Y-m-d')}.csv";

        $headers = [
            'Content-Type' => 'text/csv; charset=UTF-8',
            'Content-Disposition' => "attachment; filename=\"{$filename}\"",
        ];

        $callback = function () use ($report) {
            $file = fopen('php://output', 'w');
            fwrite($file, "\xEF\xBB\xBF"); // UTF-8 BOM

            fputcsv($file, ['클라이언트', '총 리뷰', '이관 리뷰', '실패 리뷰', '성공률']);
            foreach ($report->clientStatistics as $stat) {
                fputcsv($file, [
                    $stat->client_name ?? $stat->client_id,
                    $stat->total_reviews,
                    $stat->transferred_reviews,
                    $stat->failed_reviews,
                    $stat->success_rate . '%',
                ]);
            }

            fclose($file);
        };

        return response()->stream($callback, 200, $headers);
    }

    public function sendNotification(int $id)
    {
        $report = DailyReport::findOrFail($id);

        // Sprint 3의 NotificationSetting 확인
        $setting = \App\Models\NotificationSetting::current();
        if (!$setting->alimtalk_enabled) {
            return response()->json(['message' => '알림톡이 비활성화되어 있습니다.'], 422);
        }

        // TODO: DailyReportNotification 클래스 구현 후 발송 로직 추가
        return response()->json(['message' => '알림 발송 기능은 구현 중입니다.'], 501);
    }
}
```

**Step 3: Add routes**

`routes/api.php`의 `review` prefix 그룹 내:

```php
use App\Http\Controllers\Review\DailyReportController;

Route::get('daily-reports', [DailyReportController::class, 'index']);
Route::get('daily-reports/analytics', [DailyReportController::class, 'analytics']);
Route::get('daily-reports/{id}', [DailyReportController::class, 'show']);
Route::post('daily-reports/generate', [DailyReportController::class, 'generate']);
Route::get('daily-reports/{id}/download', [DailyReportController::class, 'download']);
Route::post('daily-reports/{id}/send-notification', [DailyReportController::class, 'sendNotification']);
```

**Step 4: Run tests**

Run: `cd SeoulVenturesGroupware && vendor/bin/phpunit tests/Feature/Review/DailyReportControllerTest.php -v`
Expected: PASS

**Step 5: Commit**

```bash
cd SeoulVenturesGroupware
git add app/Http/Controllers/Review/DailyReportController.php routes/api.php tests/Feature/Review/DailyReportControllerTest.php
git commit -m "feat: DailyReport API 컨트롤러 및 라우트 추가"
```

---

## Task 12: DailyReport — 프론트엔드 목록 페이지

**Files:**
- Create: `SeoulVenturesGroupware/frontend/resources/ts/api/entities/review/dailyReports.ts`
- Create: `SeoulVenturesGroupware/frontend/resources/ts/pages/review/daily-reports/index.vue`

**Step 1: API 엔티티 생성**

```typescript
// dailyReports.ts
import { type ApiResponse, download, get, post } from '@/api'

export interface DailyReport {
  id: number
  report_date: string
  total_clients: number
  active_clients: number
  total_reviews: number
  transferred_reviews: number
  failed_reviews: number
  success_rate: number
  status_summary: Record<string, unknown> | null
  top_clients: Record<string, unknown>[] | null
  client_statistics?: DailyClientStatistic[]
  driver_statistics?: DailyDriverStatistic[]
}

export interface DailyClientStatistic {
  id: number
  client_id: number
  client_name?: string
  total_reviews: number
  transferred_reviews: number
  failed_reviews: number
  success_rate: number
}

export interface DailyDriverStatistic {
  id: number
  driver_code: string
  driver_name?: string
  total_reviews: number
  transferred_reviews: number
  failed_reviews: number
  success_rate: number
}

export const dailyReportsApi = {
  list: (params?: { start_date?: string; end_date?: string; page?: number; per_page?: number }): Promise<ApiResponse<{ data: DailyReport[]; current_page: number; last_page: number; per_page: number; total: number }>> =>
    get('/review/daily-reports', params as Record<string, unknown>),

  show: (id: number): Promise<ApiResponse<DailyReport>> =>
    get(`/review/daily-reports/${id}`),

  generate: (date: string, force?: boolean): Promise<ApiResponse<{ message: string; report?: DailyReport }>> =>
    post('/review/daily-reports/generate', { date, force }),

  analytics: (): Promise<ApiResponse<DailyReport[]>> =>
    get('/review/daily-reports/analytics'),

  download: (id: number): Promise<ApiResponse<Blob>> =>
    download(`/review/daily-reports/${id}/download`),

  sendNotification: (id: number): Promise<ApiResponse<{ message: string }>> =>
    post(`/review/daily-reports/${id}/send-notification`),
}
```

**Step 2: 페이지 컴포넌트 생성**

```vue
<!-- daily-reports/index.vue -->
<script setup lang="ts">
import { ref, onMounted } from 'vue'
import { dailyReportsApi, type DailyReport } from '@/api/entities/review/dailyReports'

definePage({
  meta: {
    title: '일일 리포트',
    action: 'read',
    subject: 'DailyReport',
  },
})

const { snackbar, handleError } = useErrorHandler()

const loading = ref(false)
const reports = ref<DailyReport[]>([])
const page = ref(1)
const totalPages = ref(1)
const perPage = ref(20)
const startDate = ref('')
const endDate = ref('')
const generating = ref(false)
const generateDialog = ref(false)
const generateDate = ref('')
const detailDialog = ref(false)
const selectedReport = ref<DailyReport | null>(null)

const headers = [
  { title: '날짜', key: 'report_date', width: '120px' },
  { title: '총 리뷰', key: 'total_reviews', width: '100px' },
  { title: '이관 성공', key: 'transferred_reviews', width: '100px' },
  { title: '실패', key: 'failed_reviews', width: '80px' },
  { title: '성공률', key: 'success_rate', width: '100px' },
  { title: '활성 고객사', key: 'active_clients', width: '100px' },
  { title: '액션', key: 'actions', width: '140px', sortable: false },
]

const loadReports = async () => {
  loading.value = true
  try {
    const params: Record<string, unknown> = { page: page.value, per_page: perPage.value }
    if (startDate.value) params.start_date = startDate.value
    if (endDate.value) params.end_date = endDate.value

    const { success, data, error } = await dailyReportsApi.list(params)
    if (success && data) {
      reports.value = data.data
      totalPages.value = data.last_page
    } else if (error) {
      handleError(error, { notificationMessage: '리포트를 불러오는데 실패했습니다.' })
    }
  } catch (error) {
    handleError(error, { notificationMessage: '리포트를 불러오는데 실패했습니다.' })
  } finally {
    loading.value = false
  }
}

const generateReport = async () => {
  if (!generateDate.value) return
  generating.value = true
  try {
    const { success, data, error } = await dailyReportsApi.generate(generateDate.value)
    if (success) {
      snackbar.success(data?.message ?? '리포트가 생성되었습니다.')
      generateDialog.value = false
      loadReports()
    } else if (error) {
      handleError(error, { notificationMessage: '리포트 생성에 실패했습니다.' })
    }
  } catch (error) {
    handleError(error, { notificationMessage: '리포트 생성에 실패했습니다.' })
  } finally {
    generating.value = false
  }
}

const downloadReport = async (report: DailyReport) => {
  await dailyReportsApi.download(report.id)
}

const showDetail = async (report: DailyReport) => {
  try {
    const { success, data } = await dailyReportsApi.show(report.id)
    if (success && data) {
      selectedReport.value = data
      detailDialog.value = true
    }
  } catch (error) {
    handleError(error, { notificationMessage: '상세 정보를 불러오는데 실패했습니다.' })
  }
}

onMounted(loadReports)
</script>

<template>
  <VRow>
    <VCol cols="12">
      <VCard>
        <VCardTitle class="d-flex align-center justify-space-between">
          <span>일일 리포트</span>
          <VBtn color="primary" @click="generateDialog = true">리포트 생성</VBtn>
        </VCardTitle>
        <VCardText>
          <!-- 필터 -->
          <VRow dense class="mb-4">
            <VCol cols="12" md="3">
              <VTextField v-model="startDate" type="date" label="시작일" density="compact" variant="outlined" hide-details />
            </VCol>
            <VCol cols="12" md="3">
              <VTextField v-model="endDate" type="date" label="종료일" density="compact" variant="outlined" hide-details />
            </VCol>
            <VCol cols="12" md="2" class="d-flex align-center">
              <VBtn color="primary" variant="outlined" @click="page = 1; loadReports()">검색</VBtn>
            </VCol>
          </VRow>

          <!-- 테이블 -->
          <VDataTable
            :headers="headers"
            :items="reports"
            :loading="loading"
            density="compact"
            :items-per-page="perPage"
            hide-default-footer
          >
            <template #item.report_date="{ item }">
              {{ item.report_date?.slice(0, 10) }}
            </template>
            <template #item.success_rate="{ item }">
              <VChip
                :color="item.success_rate >= 95 ? 'success' : item.success_rate >= 80 ? 'warning' : 'error'"
                size="small"
              >
                {{ item.success_rate }}%
              </VChip>
            </template>
            <template #item.actions="{ item }">
              <VBtn icon="tabler-eye" variant="text" size="small" @click="showDetail(item)" />
              <VBtn icon="tabler-download" variant="text" size="small" @click="downloadReport(item)" />
            </template>
          </VDataTable>

          <div class="d-flex justify-center mt-4">
            <VPagination v-model="page" :length="totalPages" :total-visible="7" @update:model-value="loadReports" />
          </div>
        </VCardText>
      </VCard>
    </VCol>

    <!-- 생성 다이얼로그 -->
    <VDialog v-model="generateDialog" max-width="400">
      <VCard>
        <VCardTitle>리포트 생성</VCardTitle>
        <VCardText>
          <VTextField v-model="generateDate" type="date" label="날짜" variant="outlined" />
        </VCardText>
        <VCardActions>
          <VSpacer />
          <VBtn @click="generateDialog = false">취소</VBtn>
          <VBtn color="primary" :loading="generating" @click="generateReport">생성</VBtn>
        </VCardActions>
      </VCard>
    </VDialog>

    <!-- 상세 다이얼로그 -->
    <VDialog v-model="detailDialog" max-width="900" scrollable>
      <VCard v-if="selectedReport">
        <VCardTitle>{{ selectedReport.report_date?.slice(0, 10) }} 리포트 상세</VCardTitle>
        <VCardText>
          <h4 class="mb-2">클라이언트별 통계</h4>
          <VDataTable
            :headers="[
              { title: '클라이언트', key: 'client_name' },
              { title: '총 리뷰', key: 'total_reviews' },
              { title: '이관', key: 'transferred_reviews' },
              { title: '실패', key: 'failed_reviews' },
              { title: '성공률', key: 'success_rate' },
            ]"
            :items="selectedReport.client_statistics ?? []"
            density="compact"
            :items-per-page="50"
          >
            <template #item.success_rate="{ item }">{{ item.success_rate }}%</template>
          </VDataTable>
        </VCardText>
        <VCardActions>
          <VSpacer />
          <VBtn @click="detailDialog = false">닫기</VBtn>
        </VCardActions>
      </VCard>
    </VDialog>
  </VRow>
</template>
```

**Step 3: Commit**

```bash
cd SeoulVenturesGroupware
git add frontend/resources/ts/api/entities/review/dailyReports.ts frontend/resources/ts/pages/review/daily-reports/index.vue
git commit -m "feat: DailyReport 프론트엔드 목록/상세/생성 페이지 추가"
```

---

## 전체 커밋 체크포인트

| Task | 커밋 메시지 | 내용 |
|---|---|---|
| 1 | `test: 무신사 체험단 includeExperience 저장 테스트 추가` | 백엔드 테스트 |
| 2 | `feat: 무신사 체험단 리뷰 수집 모드 설정 UI 추가` | 프론트엔드 |
| 3 | `test: 쿠팡 판매자 필터 sellerNames 저장 테스트 추가` | 백엔드 테스트 |
| 4 | `feat: 쿠팡 판매자 필터 설정 UI 추가` | 프론트엔드 |
| 5 | `feat: NotificationSetting 모델 및 마이그레이션 추가` | 모델/DB |
| 6 | `feat: NotificationSetting API 컨트롤러 및 라우트 추가` | API |
| 7 | `feat: NotificationSetting 프론트엔드 설정 페이지 추가` | 프론트엔드 |
| 8 | `feat: MongoDB 리뷰 조회 서비스 및 모델 추가` | 서비스/모델 |
| 9 | `feat: MongoDB 리뷰 조회 API 컨트롤러 및 라우트 추가` | API |
| 10 | `feat: MongoDB 리뷰 조회 프론트엔드 컴포넌트 추가` | 프론트엔드 |
| 11 | `feat: DailyReport API 컨트롤러 및 라우트 추가` | API |
| 12 | `feat: DailyReport 프론트엔드 목록/상세/생성 페이지 추가` | 프론트엔드 |
