pipeline {
  agent any

  stages {
    stage('Run ETL Ares con fallback') {
      steps {
        sh 'bash infra/scripts/run_etl_with_fallback.sh'
      }
    }
  }
}
