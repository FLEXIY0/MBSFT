# MBSFT Persistent Service

## Описание

MBSFT v4.7.0+ включает поддержку persistent service для Termux, который обеспечивает непрерывную работу серверов даже когда приложение Termux закрыто.

## Возможности

- **Неубиваемый процесс**: Сервис использует `termux-services` (runit) для создания надежного фонового процесса
- **Wake Lock**: Предотвращает завершение процесса системой Android
- **Постоянная proot-сессия**: Поддерживает Ubuntu proot environment активным
- **SSH всегда доступен**: SSH daemon (порт 2222) работает постоянно
- **Watchdog/Autosave сохраняются**: Все фоновые процессы серверов продолжают работать
- **Автоматический перезапуск**: При сбое сервис автоматически перезапускается

## Установка

### Автоматическая установка (новые пользователи)

При запуске `bootstrap.sh` версии 5.1.0+ сервис устанавливается автоматически:

```bash
curl -sL https://raw.githubusercontent.com/FLEXIY0/MBSFT/main/bootstrap.sh | bash
```

После установки:

1. **Перезапустите Termux** (полностью закройте и откройте приложение)
2. Включите сервис:
   ```bash
   sv-enable mbsft
   sv up mbsft
   ```

### Ручная установка (существующие пользователи)

Если у вас уже установлен MBSFT:

1. Установите необходимые пакеты:
   ```bash
   pkg install termux-services termux-api -y
   ```

2. Перезапустите Termux

3. Создайте структуру сервиса:
   ```bash
   mkdir -p $PREFIX/var/service/mbsft/log
   ```

4. Запустите MBSFT и выберите: **Сервис → Установить сервис**

## Управление сервисом

### Через меню MBSFT

Запустите `mbsft` и выберите пункт **"Сервис"** в главном меню.

Доступные опции:
- Запустить/остановить сервис
- Перезапустить сервис
- Включить/отключить автозапуск
- Посмотреть логи
- Удалить сервис

### Через командную строку

```bash
# Запуск
sv up mbsft

# Остановка
sv down mbsft

# Перезапуск
sv restart mbsft

# Статус
sv status mbsft

# Включить автозапуск
sv-enable mbsft

# Отключить автозапуск
sv-disable mbsft

# Просмотр логов
tail -f ~/.mbsft-service-logs/current
```

## Как это работает

### Архитектура

```
Android OS
  ├─ Termux App
  │   ├─ service-daemon (runit)
  │   │   └─ mbsft service
  │   │       ├─ termux-wake-lock (держит процесс активным)
  │   │       └─ proot-distro login ubuntu
  │   │           ├─ sshd (порт 2222)
  │   │           └─ monitor loop (проверяет статус каждые 10 сек)
  │   │               ├─ server1 (tmux + watchdog + autosave)
  │   │               ├─ server2 (tmux + watchdog + autosave)
  │   │               └─ ...
```

### Файлы сервиса

- **`$PREFIX/var/service/mbsft/run`** - главный скрипт сервиса
- **`$PREFIX/var/service/mbsft/log/run`** - скрипт логирования (svlogd)
- **`$PREFIX/var/service/mbsft/finish`** - скрипт очистки при остановке
- **`~/.mbsft-service-logs/`** - директория с логами

### Что делает сервис

1. Захватывает wake-lock через `termux-wake-lock`
2. Запускает `proot-distro login ubuntu` с bind mount `/termux-home`
3. Внутри proot запускает SSH daemon на порту 2222
4. Запускает мониторинг-луп, который:
   - Проверяет состояние proot-сессии каждые 10 секунд
   - При падении автоматически перезапускает
   - Логирует все события
5. При остановке сервиса:
   - Освобождает wake-lock
   - Корректно завершает proot-сессию

## SSH доступ

Когда сервис запущен, SSH daemon внутри Ubuntu proot доступен на порту 2222:

```bash
# С другого устройства в той же сети:
ssh root@<IP_адрес_устройства> -p 2222

# Из самого Termux:
ssh root@localhost -p 2222
```

Для настройки SSH:
1. Запустите `mbsft`
2. Выберите **SSH → Add SSH key**
3. Или установите пароль: войдите в proot и выполните `passwd`

## Требования

- **Termux** (актуальная версия)
- **termux-services** - для runit service management
- **termux-api** - для wake-lock функциональности
- **proot-distro** - для Ubuntu окружения
- **Ubuntu distro** - установленная через proot-distro

## Ограничения PRoot

**Важно**: PRoot не может отделяться от процессов из-за ограничения ptrace(). Это означает:

- ❌ Нельзя запустить daemon внутри proot и закрыть proot-сессию
- ✅ Сервис решает это, поддерживая proot-сессию постоянно открытой
- ✅ SSH daemon работает, потому что сессия не закрывается

## Отладка

### Проверка статуса сервиса

```bash
sv status mbsft
```

### Просмотр логов

```bash
# Последние 50 строк
tail -n 50 ~/.mbsft-service-logs/current

# Следить в реальном времени
tail -f ~/.mbsft-service-logs/current
```

### Проверка процессов

```bash
# Проверить proot процессы
pgrep -f proot-distro

# Проверить SSH внутри proot
proot-distro login ubuntu -- pgrep -x sshd
```

### Типичные проблемы

#### Сервис не запускается

1. Убедитесь, что Termux перезапущен после установки termux-services
2. Проверьте наличие service-daemon: `pgrep -f service-daemon`
3. Проверьте логи: `tail ~/.mbsft-service-logs/current`

#### SSH недоступен

1. Проверьте, что сервис запущен: `sv status mbsft`
2. Проверьте логи сервиса на ошибки запуска SSH
3. Проверьте SSH вручную:
   ```bash
   proot-distro login ubuntu -- /usr/sbin/sshd -p 2222
   ```

#### Сервис постоянно перезапускается

1. Проверьте логи на ошибки: `tail -f ~/.mbsft-service-logs/current`
2. Убедитесь, что Ubuntu distro установлен: `proot-distro list`
3. Проверьте доступность памяти на устройстве

## Источники и документация

- [termux-services](https://github.com/termux/termux-services) - Termux service management
- [runit](http://smarden.org/runit/) - Unix init scheme with service supervision
- [proot-distro](https://github.com/termux/proot-distro) - Utility for managing Linux distributions in Termux

## Версии

- **v5.1.0** (bootstrap.sh) - Автоматическая установка сервиса
- **v4.7.0** (mbsft.sh) - Добавлено меню управления сервисом
- **v1.0.0** (service) - Первая версия persistent service

## Авторы

- MBSFT Project - https://github.com/FLEXIY0/MBSFT
