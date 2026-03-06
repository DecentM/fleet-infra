#!/bin/sh
set -ex

BASE_URL="http://synapse.app-matrix.svc:8008"
AUTH="Authorization: Bearer ${SYNAPSE_ADMIN_TOKEN}"
POLL_INTERVAL=5
POLL_TIMEOUT=300
DELETE_BODY='{"purge":true}'

ROOM_LIST="/tmp/foreign_rooms.txt"
RESULT_FILE="/tmp/purge_results.txt"
: > "${ROOM_LIST}"
printf '0 0\n' > "${RESULT_FILE}"

offset=0
echo "Discovering rooms with zero local members..."

while true; do
  response=$(curl -sf -H "${AUTH}" \
    "${BASE_URL}/_synapse/admin/v1/rooms?order_by=joined_local_members&dir=b&limit=100&from=${offset}")

  total_rooms=$(printf '%s' "${response}" | grep -o '"total_rooms":[0-9]*' | head -1 | sed 's/"total_rooms"://' || true)
  if [ -n "${total_rooms}" ]; then
    echo "Total rooms in server - ${total_rooms}"
  fi

  room_ids=$(printf '%s' "${response}" | grep -o '"room_id":"[^"]*"' | sed 's/"room_id":"//;s/"//' || true)
  local_members=$(printf '%s' "${response}" | grep -o '"joined_local_members":[0-9]*' | sed 's/"joined_local_members"://' || true)

  room_count=$(printf '%s\n' "${room_ids}" | grep -c '.' || true)
  if [ "${room_count}" -eq 0 ]; then
    echo "No more rooms in this page, done discovering."
    break
  fi

  i=1
  while [ "${i}" -le "${room_count}" ]; do
    rid=$(printf '%s\n' "${room_ids}" | sed -n "${i}p")
    members=$(printf '%s\n' "${local_members}" | sed -n "${i}p")

    if [ "${members}" = "0" ]; then
      printf '%s\n' "${rid}" >> "${ROOM_LIST}"
    fi

    i=$((i + 1))
  done

  next_batch=$(printf '%s' "${response}" | grep -o '"next_batch":[0-9]*' | head -1 | sed 's/"next_batch"://' || true)
  if [ -z "${next_batch}" ]; then
    echo "No next_batch, done discovering."
    break
  fi

  offset=${next_batch}
done

total_foreign=$(wc -l < "${ROOM_LIST}" | tr -d ' ')
echo "Found ${total_foreign} rooms with zero local members."

if [ "${total_foreign}" -eq 0 ]; then
  echo "Nothing to purge. Exiting."
  exit 0
fi

success_count=0
fail_count=0
current=0

while IFS= read -r room_id; do
  if [ -z "${room_id}" ]; then
    continue
  fi

  current=$((current + 1))
  echo "[${current}/${total_foreign}] Deleting room - ${room_id}"

  encoded_room_id=$(printf '%s' "${room_id}" | sed 's/#/%23/g; s/:/%3A/g')

  delete_response=$(curl -sf -X DELETE \
    -H "${AUTH}" \
    -H "Content-Type: application/json" \
    -d "${DELETE_BODY}" \
    "${BASE_URL}/_synapse/admin/v2/rooms/${encoded_room_id}" 2>&1) || {
    echo "  FAILED to issue delete for ${room_id}"
    fail_count=$((fail_count + 1))
    continue
  }

  delete_id=$(printf '%s' "${delete_response}" | grep -o '"delete_id":"[^"]*"' | head -1 | sed 's/"delete_id":"//;s/"//' || true)

  if [ -z "${delete_id}" ]; then
    echo "  FAILED to get delete_id for ${room_id}"
    fail_count=$((fail_count + 1))
    continue
  fi

  echo "  delete_id=${delete_id}, polling status..."

  elapsed=0
  status="unknown"
  while [ "${elapsed}" -lt "${POLL_TIMEOUT}" ]; do
    sleep "${POLL_INTERVAL}"
    elapsed=$((elapsed + POLL_INTERVAL))

    status_response=$(curl -sf -H "${AUTH}" \
      "${BASE_URL}/_synapse/admin/v2/rooms/${encoded_room_id}/delete_status" 2>&1) || {
      echo "  Warning - failed to poll status at ${elapsed}s"
      continue
    }

    status=$(printf '%s' "${status_response}" | grep -o '"status":"[^"]*"' | head -1 | sed 's/"status":"//;s/"//' || true)

    if [ "${status}" = "complete" ]; then
      echo "  SUCCESS - ${room_id} purged (${elapsed}s)"
      success_count=$((success_count + 1))
      break
    elif [ "${status}" = "failed" ]; then
      echo "  FAILED - ${room_id} delete failed (${elapsed}s)"
      fail_count=$((fail_count + 1))
      break
    fi
  done

  if [ "${status}" != "complete" ] && [ "${status}" != "failed" ]; then
    echo "  TIMEOUT - ${room_id} still ${status} after ${POLL_TIMEOUT}s"
    fail_count=$((fail_count + 1))
  fi
done < "${ROOM_LIST}"

echo ""
echo "=== Foreign Room Purge Summary ==="
echo "Total foreign rooms found - ${total_foreign}"
echo "Successfully purged - ${success_count}"
echo "Failed - ${fail_count}"
echo "=================================="

if [ "${fail_count}" -gt 0 ]; then
  exit 1
fi

exit 0
