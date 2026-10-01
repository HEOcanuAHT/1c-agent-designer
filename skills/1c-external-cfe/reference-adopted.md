# Adopted-объекты в расширении (XML)

Ручная сборка заимствований хрупкая. Предпочтительно: заимствовать в Конфигураторе → dump XML расширения.  
Ниже — минимум, без которого `ibcmd config import --extension=…` падает.

## Частые ошибки import

| Симптом в `.1c/cfe-pack.log` | Причина / фикс |
|------------------------------|----------------|
| ожидалось `ChildObjects` | у Adopted нет `<ChildObjects/>` (хотя бы пустой) |
| нет содержимого `InternalInfo` | нет `GeneratedType` (и/или ContainedObject по типу) |
| прочие ошибки структуры | нужны и `GeneratedType`, и `PropertyState` (Module=Extended), и `ChildObjects` |

## Общие правила

1. `ObjectBelonging` = `Adopted`.
2. `ExtendedConfigurationObject` = uuid объекта **основной** конфигурации.
3. Uuid самого MetaDataObject в расширении — **свой** (не обязан совпадать с основной; для CommonModule часто отдельный).
4. `KeepMappingToExtendedConfigurationObjectsByIDs` в корне расширения обычно `true`.
5. У DataProcessor в `GeneratedType` — **новые** `TypeId`/`ValueId` (не слепо копировать с основной).
6. `<NamePrefix>` в корне расширения не оставлять пустым.

## Каркас Adopted CommonModule

```xml
<MetaDataObject …>
  <CommonModule uuid="<<<<<<<<-NEW-UUID-IN-EXTENSION>>>>>>>>">
    <InternalInfo>
      <xr:GeneratedType name="CommonModule.ИмяМодуляОсновной" category="Manager">
        <xr:TypeId>…новый…</xr:TypeId>
        <xr:ValueId>…новый…</xr:ValueId>
      </xr:GeneratedType>
    </InternalInfo>
    <Properties>
      <ObjectBelonging>Adopted</ObjectBelonging>
      <Name>ИмяМодуляОсновной</Name>
      <Comment/>
      <ExtendedConfigurationObject><<<<<<<<-UUID-ИЗ-ОСНОВНОЙ-Configuration>>>>>>>></ExtendedConfigurationObject>
      <!-- плюс свойства модуля, которые расширяете -->
    </Properties>
    <ChildObjects/>
  </CommonModule>
</MetaDataObject>
```

Модуль BSL: `…/Ext/Module.bsl` с `&Вместо` / `&Перед` / `&После` по стандартам.

В метаданных формы/модуля расширения для перехвата: `PropertyState` → `Module` / `ObjectModule` = `Extended`.

## Каркас Adopted DataProcessor

Те же правила + обязательно:

- `InternalInfo` с `GeneratedType` (`DataProcessorObject.…` / менеджер по факту выгрузки)
- пустой или заполненный `<ChildObjects/>`
- новые TypeId/ValueId
- при расширении модуля объекта: `PropertyState` ObjectModule=`Extended` и файл `Ext/ObjectModule.bsl`

## Protected-модули (ObjectModule.bin / нет .bsl)

Если в основной конфе модуль — image (защита), `.bsl` нет:

1. Искать точки входа по **UTF-8 строкам** внутри `.bin` (имена процедур, литералы).
2. В расширении — `&Вместо ИмяНайденнойПроцедуры` (или Перед/После) в своём модуле Adopted-объекта.
3. Не ждать появления исходника `.bsl` из дампа.

Пример паттерна (не копировать бизнес-логику кейса): найти процедуру по строкам → `&Вместо` → подставить безопасные значения → `ПродолжитьВызов()`.

## Что не делать

- Не собирать Adopted «на глаз» без шаблона/дампа из Конфигуратора.
- Не ставить `ExtendedConfigurationObject` = uuid из расширения.
- Не оставлять Adopted DataProcessor без `ChildObjects` и без `GeneratedType`.
