#!/bin/bash

# Definição do caminho padrão para a base de dados
BASE_DE_DADOS="$HOME/.protecao"

# Função para mostrar a mensagem de ajuda
mostrar_ajuda() {
    echo "Uso: ./vigia_pirata [-f <ficheiro>] [<nome_base_de_dados>] [{-p <diretoria[<diretoria>] | -v}]"
    echo "-p : Protege e guarda informação acerca de uma ou mais diretorias"
    echo "-v : Verifica alterações em ficheiros desde que foram protegidos"
    echo "-f : Indicação do nome do ficheiro onde a base de dados será guardada"
    echo "     (Por defeito será \$HOME/.protecao)"
}

# Função para proteger os diretórios especificados
proteger() {
    echo "A proteger diretórios..."
    for dir in "$@"; do
        if [ -d "$dir" ]; then
            echo "$dir" >> "$BASE_DE_DADOS"
            find "$dir" -type f -exec stat -c "User:%U Group:%G Size:%s Perm:%a Change Time:%y %n" {} + >> "$BASE_DE_DADOS" 2>/dev/null
        else
            echo "Diretório $dir não existe."
        fi
    done
    echo "Diretórios protegidos com sucesso! Base de dados $BASE_DE_DADOS criada."
    # Definir a base de dados como read only
    chmod 400 "$BASE_DE_DADOS"
}

# Função para verificar modificações nos arquivos protegidos
verificar() {
    local database="$1"  # Recebe o nome da base de dados como argumento
    echo "Verificando modificações..."
    if [ ! -f "$database" ]; then
        echo "Nenhuma base de dados encontrada. Execute 'vigia_pirata -p' para proteger diretórios."
        exit 1
    fi

    # Criar uma lista temporária para armazenar arquivos encontrados
    temp_file=$(mktemp)

    while read -r dir; do
        # Adicionar arquivos encontrados ao arquivo temporário
        find "$dir" -type f -exec stat -c "User:%U Group:%G Size:%s Perm:%a Change Time:%y %n" {} + >> "$temp_file" 2>/dev/null
    done < "$database"

    # Comparar arquivos presentes na base de dados com arquivos encontrados
    diff_output=$(diff "$database" "$temp_file" | grep -v "^---")

    if [ -n "$diff_output" ]; then
        echo "Diferenças detectadas:"
        while IFS= read -r line; do
            if [[ $line == "<"* ]]; then
                arquivo=$(echo "${line:2}" | awk '{print $NF}')
                protegido=$(dirname "$arquivo")
                if [[ "$protegido" != "$(dirname "$database")" && ! -d "$arquivo" ]]; then
                    # Verifica se o arquivo também está presente nas linhas começando com ">"
                    arquivo_modificado=false
                    while IFS= read -r diff_line; do
                        if [[ $diff_line == ">"* && "${diff_line:2}" == *"$arquivo" ]]; then
                            arquivo_modificado=true
                            info_atual=$(echo "$diff_line" | cut -d " " -f 2-)
                            break
                        fi
                    done <<< "$diff_output"

                    if [ "$arquivo_modificado" = true ]; then
                        echo "------------------------------------------------------"
                        echo "Arquivo Modificado: $arquivo"
                        echo "Informação Inicial: ${line:2}"
                        echo "Informação Atual: $info_atual"
                    else
                        echo "------------------------------------------------------"
                        echo "Arquivo Removido: $arquivo"
                        echo "Informação Inicial: ${line:2}"
                    fi
                fi
            elif [[ $line == ">"* ]]; then
                arquivo=$(echo "${line:2}" | awk '{print $NF}')
                protegido=$(dirname "$arquivo")
                if [[ "$protegido" != "$(dirname "$database")" ]]; then
                    # Verifica se o arquivo também está presente nas linhas começando com "<"
                    arquivo_modificado=false
                    while IFS= read -r diff_line; do
                        if [[ $diff_line == "<"* && "${diff_line:2}" == *"$arquivo" ]]; then
                            arquivo_modificado=true
                            break
                        fi
                    done <<< "$diff_output"

                    if [ "$arquivo_modificado" = false ]; then
                        echo "------------------------------------------------------"
                        echo "Arquivo Novo: $arquivo"
                        echo "Informação Atual: ${line:2}"
                    fi
                fi
            fi
        done <<< "$diff_output"
    else
        echo "Nenhuma diferença encontrada."
    fi

    # Remover arquivo temporário
    rm "$temp_file"
}

# Verificar a opção passada na linha de comando
while getopts ":pvf:" opt; do
    case $opt in
        p)
            p_option=true
            ;;
        v)
            v_option=true
            ;;
        f)
            f_option=true
            BASE_DE_DADOS="$OPTARG"
            ;;
        \?)
            echo "Opção inválida: -$OPTARG" >&2
            mostrar_ajuda
            exit 1
            ;;
    esac
done

# Verificar se as opções -p e -v foram passadas simultaneamente
if [[ "$p_option" == true && "$v_option" == true ]]; then
    echo "Opções -p e -v não podem ser usadas simultaneamente."
    mostrar_ajuda
    exit 1
fi

# Verificar se a opção -f foi passada sem o nome da base de dados
if [ "$f_option" == true ] && [ -z "$BASE_DE_DADOS" ]; then
    echo "A opção -f requer o nome do arquivo da base de dados."
    mostrar_ajuda
    exit 1
fi

# Executar a ação correspondente
if [ "$p_option" == true ]; then
    proteger "${@:OPTIND}"
elif [ "$v_option" == true ]; then
    verificar "$BASE_DE_DADOS"
elif [ $# -eq 0 ]; then
    verificar "$BASE_DE_DADOS"
else
    mostrar_ajuda
    exit 1
fi

