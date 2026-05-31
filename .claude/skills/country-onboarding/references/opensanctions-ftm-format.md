# OpenSanctions FTM → Senzing JSONL Conversion

## FTM entity shape (input)

OpenSanctions publishes entities in FollowTheMoney (FTM) format, one JSON object per line:

```json
{
  "id": "Q7747",
  "caption": "Vladimir Putin",
  "schema": "Person",
  "properties": {
    "name": ["Vladimir Vladimirovich Putin"],
    "birthDate": ["1952-10-07"],
    "nationality": ["ru"],
    "gender": ["male"],
    "position": ["President of Russia"],
    "country": ["ru"],
    "topics": ["sanction"]
  },
  "datasets": ["us_ofac_sdn", "eu_fsf"]
}
```

## Senzing JSONL shape (output — what Watchman reads)

```json
{
  "DATA_SOURCE": "AE_LOCAL_TERRORISTS",
  "RECORD_ID": "Q7747",
  "RECORD_TYPE": "PERSON",
  "NAME_FULL": "Vladimir Vladimirovich Putin",
  "DATE_OF_BIRTH": "1952-10-07",
  "NATIONALITY": "RU",
  "ADDR_COUNTRY": "RU",
  "GENDER": "M"
}
```

## Field mapping

| FTM field | Senzing field | Transform |
|---|---|---|
| `id` | `RECORD_ID` | as-is |
| `properties.name[0]` | `NAME_FULL` (Person) or `NAME_ORG` (Org) | first value |
| `properties.birthDate[0]` | `DATE_OF_BIRTH` | as-is (ISO 8601) |
| `properties.nationality[0]` | `NATIONALITY` | uppercase |
| `properties.country[0]` | `ADDR_COUNTRY` | uppercase |
| `properties.gender[0]` | `GENDER` | first letter uppercase (M/F) |
| `properties.idNumber[0]` | `NATIONAL_ID_NUMBER` | as-is |
| `properties.passportNumber[0]` | `PASSPORT_NUMBER` | as-is |
| `properties.address[0]` | `ADDR_LINE1` | as-is |

## Schema → RECORD_TYPE mapping

| FTM schema | Senzing RECORD_TYPE |
|---|---|
| `Person` | `PERSON` |
| `Organization` | `ORGANIZATION` |
| `Company` | `ORGANIZATION` |
| `LegalEntity` | `ORGANIZATION` |

## Conversion script (Python one-liner)

```bash
python3 -c "
import json, sys
dataset = sys.argv[1].upper()
for line in sys.stdin:
    e = json.loads(line)
    if e.get('schema') not in ('Person','Organization','Company','LegalEntity'): continue
    p = e.get('properties', {})
    is_person = e['schema'] == 'Person'
    r = {
        'DATA_SOURCE': dataset,
        'RECORD_ID': e['id'],
        'RECORD_TYPE': 'PERSON' if is_person else 'ORGANIZATION',
    }
    name = (p.get('name') or [''])[0]
    if is_person:
        r['NAME_FULL'] = name
    else:
        r['NAME_ORG'] = name
    if p.get('birthDate'): r['DATE_OF_BIRTH'] = p['birthDate'][0]
    if p.get('nationality'): r['NATIONALITY'] = p['nationality'][0].upper()
    if p.get('country'): r['ADDR_COUNTRY'] = p['country'][0].upper()
    if p.get('gender'): r['GENDER'] = p['gender'][0][0].upper()
    if p.get('passportNumber'): r['PASSPORT_NUMBER'] = p['passportNumber'][0]
    if p.get('idNumber'): r['NATIONAL_ID_NUMBER'] = p['idNumber'][0]
    print(json.dumps(r))
" DATASET_NAME < /tmp/dataset.ftm.json > /tmp/dataset.senzing.jsonl
```

## Data source URL pattern

```
https://data.opensanctions.org/datasets/latest/<dataset_name>/entities.ftm.json
```

Index of all datasets:
```
https://data.opensanctions.org/datasets/latest/index.json
```

Filter by country: dataset names are prefixed with the ISO 3166-1 alpha-2 code (lowercase), e.g., `ae_local_terrorists`, `id_dttot`, `fr_tresor_gels_avoir`.
