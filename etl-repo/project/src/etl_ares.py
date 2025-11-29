"""Módulo PoC para project.src.etl_ares
Este módulo se ejecuta con: python -m project.src.etl_ares
"""
import time
import os


def main():
    print("🏁 Iniciando ETL Ares (module) - project.src.etl_ares")
    # Ejemplo de uso de variables de entorno o configuración
    scenario = os.environ.get('SCENARIO', 'UNKNOWN')
    print(f"🔎 SCENARIO env: {scenario}")
    time.sleep(1)
    print("📦 Procesando datos...")
    time.sleep(1)
    print("✅ ETL Ares finalizado correctamente.")


if __name__ == '__main__':
    main()
