#!/usr/bin/env bash
set -euo pipefail

source ./script/process/lib/quality-common.sh

quality_initialize_runtime
quality_exit_if_no_changed_files "quality-quick"
quality_prepare_standard_context

if quality_has_any_solidity_change; then
    quality_print_solidity_context "quality-quick"

    if [ "${#solidity_files[@]}" -gt 0 ]; then
        echo "[quality-quick] bash ./script/process/check-solhint.sh (changed Solidity files only)"
        bash ./script/process/check-solhint.sh "${solidity_files[@]}"
        echo "[quality-quick] forge fmt --check (changed Solidity files only)"
        forge fmt --check "${solidity_files[@]}"
    fi

    if [ "$has_src_sol" -eq 1 ] && [ "${#src_solidity_files[@]}" -gt 0 ]; then
        echo "[quality-quick] bash ./script/process/check-natspec.sh (changed src Solidity files only)"
        bash ./script/process/check-natspec.sh "${src_solidity_files[@]}"
    fi

    echo "[quality-quick] forge build"
    forge build

    case "$classification" in
        non-semantic)
            echo "[quality-quick] skip Solidity tests (non-semantic classification)"
            ;;
        test-semantic)
            targeted_tests=()
            for file in "${changed_test_files[@]}"; do
                if [ -f "$file" ]; then
                    targeted_tests+=("$file")
                fi
            done

            if [ "${#targeted_tests[@]}" -gt 0 ]; then
                mapfile -t deduped_targeted_tests < <(printf '%s\n' "${targeted_tests[@]}" | awk '!seen[$0]++')
                for test_file in "${deduped_targeted_tests[@]}"; do
                    echo "[quality-quick] forge test --match-path $test_file"
                    forge test --match-path "$test_file"
                done
            elif [ "$has_sol_tests" -eq 1 ]; then
                echo "[quality-quick] forge test"
                forge test
            else
                echo "[quality-quick] no targeted Solidity tests selected."
            fi
            ;;
        prod-semantic|high-risk)
            echo "[quality-quick] forge test -vvv"
            forge test -vvv
            ;;
        *)
            echo "[quality-quick] skip Solidity tests (classification '$classification')"
            ;;
    esac
fi

if [ "$has_process_surface" -eq 1 ]; then
    echo "[quality-quick] default roles: $(join_by_semicolon "${process_default_roles[@]}")"
fi

if [ "${#shell_files[@]}" -gt 0 ]; then
    echo "[quality-quick] bash -n (changed shell scripts)"
    bash -n "${shell_files[@]}"
fi

if [ "${#process_js_files[@]}" -gt 0 ]; then
    echo "[quality-quick] node --check (changed process JS files)"
    node --check "${process_js_files[@]}"
fi

if [ "$has_package_metadata" -eq 1 ]; then
    echo "[quality-quick] default roles: $(join_by_semicolon "${package_default_roles[@]}")"
    echo "[quality-quick] npm ci"
    npm ci
fi

if [ "$should_run_docs_check" -eq 1 ]; then
    if [ "$has_docs_contract" -eq 1 ] && [ "$has_process_surface" -eq 0 ] && [ "$has_package_metadata" -eq 0 ]; then
        echo "[quality-quick] default roles: $(join_by_semicolon "${docs_contract_default_roles[@]}")"
    fi
    echo "[quality-quick] npm run docs:check"
    npm run docs:check
fi

if [ "$should_run_process_selftest" -eq 1 ]; then
    if [ "$has_process_surface" -eq 0 ] && [ "$has_package_metadata" -eq 0 ]; then
        echo "[quality-quick] default roles: $(join_by_semicolon "${process_default_roles[@]}")"
    fi
    echo "[quality-quick] npm run process:selftest"
    npm run process:selftest
fi

echo "[quality-quick] PASS (quick only, final verification still requires npm run quality:gate)"
